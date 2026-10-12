"""Transport receiver and recovery state machine for MoldUDP64 and ITCH 5.0."""

from __future__ import annotations

from dataclasses import dataclass

from lob_sim.events import AuditRecord
from lob_sim.feed_decoder import ITCHDecoder
from lob_sim.models import RecoveryState
from lob_sim.moldudp64 import MoldUDP64Packet, MoldUDP64Parser
from lob_sim.order_book import OrderBook


@dataclass(frozen=True, slots=True)
class PacketProcessResult:
    """Outcome of processing a transport packet."""

    success: bool
    state: RecoveryState
    expected_sequence: int
    applied_messages: int
    gap_detected: tuple[int, int] | None  # (start_seq, end_seq) if gap
    error_message: str | None
    audit_records: tuple[AuditRecord, ...]


class MoldUDP64Receiver:
    """Stateful MoldUDP64 packet receiver with sequence validation and gap recovery."""

    def __init__(
        self,
        book: OrderBook,
        initial_seq: int = 1,
        max_buffer_size: int = 1000,
    ) -> None:
        self.book: OrderBook = book
        self.expected_seq: int = initial_seq
        self.max_buffer_size: int = max_buffer_size
        self.state: RecoveryState = RecoveryState.SEQUENCED
        self.session: str | None = None

        # Out-of-order / post-gap packet buffer: sequence_number -> MoldUDP64Packet
        self._buffer: dict[int, MoldUDP64Packet] = {}

    @property
    def buffered_packet_count(self) -> int:
        return len(self._buffer)

    def process_raw_packet(self, data: bytes) -> PacketProcessResult:
        """Parse and process a raw network packet."""
        try:
            packet = MoldUDP64Parser.parse_packet(data)
        except Exception as e:
            self.state = RecoveryState.INVALID
            self.book.is_valid = False
            return PacketProcessResult(
                success=False,
                state=self.state,
                expected_sequence=self.expected_seq,
                applied_messages=0,
                gap_detected=None,
                error_message=f"Malformed MoldUDP64 packet: {e}",
                audit_records=(),
            )

        return self.process_packet(packet)

    def process_packet(self, packet: MoldUDP64Packet) -> PacketProcessResult:
        """Process an already unpacked MoldUDP64 packet through the state machine."""
        # 1. Session tracking
        if self.session is None:
            self.session = packet.session
        elif packet.session != self.session:
            self.state = RecoveryState.INVALID
            self.book.is_valid = False
            return PacketProcessResult(
                success=False,
                state=self.state,
                expected_sequence=self.expected_seq,
                applied_messages=0,
                gap_detected=None,
                error_message=f"Session mismatch: expected {self.session!r}, got {packet.session!r}",
                audit_records=(),
            )

        # 2. Heartbeat Packet
        if packet.is_heartbeat:
            return self._handle_heartbeat(packet)

        # 3. Duplicate packet check
        if packet.sequence_number < self.expected_seq:
            # Duplicate / stale packet: ignore harmlessly
            return PacketProcessResult(
                success=True,
                state=self.state,
                expected_sequence=self.expected_seq,
                applied_messages=0,
                gap_detected=None,
                error_message=f"Ignored duplicate packet with seq {packet.sequence_number} < expected {self.expected_seq}",
                audit_records=(),
            )

        # 4. Sequence gap check
        if packet.sequence_number > self.expected_seq:
            return self._handle_gap(packet)

        # 5. In-order packet (packet.sequence_number == self.expected_seq)
        return self._handle_in_order(packet)

    def _handle_heartbeat(self, packet: MoldUDP64Packet) -> PacketProcessResult:
        if packet.sequence_number > self.expected_seq:
            gap = (self.expected_seq, packet.sequence_number - 1)
            self.state = RecoveryState.GAP_DETECTED
            self.book.is_valid = False
            return PacketProcessResult(
                success=False,
                state=self.state,
                expected_sequence=self.expected_seq,
                applied_messages=0,
                gap_detected=gap,
                error_message=f"Heartbeat revealed sequence gap {gap[0]}..{gap[1]}",
                audit_records=(),
            )

        return PacketProcessResult(
            success=True,
            state=self.state,
            expected_sequence=self.expected_seq,
            applied_messages=0,
            gap_detected=None,
            error_message=None,
            audit_records=(),
        )

    def _handle_gap(self, packet: MoldUDP64Packet) -> PacketProcessResult:
        if len(self._buffer) >= self.max_buffer_size:
            self.state = RecoveryState.INVALID
            self.book.is_valid = False
            return PacketProcessResult(
                success=False,
                state=self.state,
                expected_sequence=self.expected_seq,
                applied_messages=0,
                gap_detected=None,
                error_message=f"Buffer overflow: exceeded max capacity {self.max_buffer_size}",
                audit_records=(),
            )

        gap = (self.expected_seq, packet.sequence_number - 1)
        self.state = RecoveryState.GAP_DETECTED
        self.book.is_valid = False
        self._buffer[packet.sequence_number] = packet

        return PacketProcessResult(
            success=False,
            state=self.state,
            expected_sequence=self.expected_seq,
            applied_messages=0,
            gap_detected=gap,
            error_message=f"Sequence gap detected: expected {self.expected_seq}, got {packet.sequence_number}. Buffered future packet.",
            audit_records=(),
        )

    def _handle_in_order(self, packet: MoldUDP64Packet) -> PacketProcessResult:
        applied_count = 0
        records: list[AuditRecord] = []

        # Apply current packet's messages
        for msg_bytes in packet.messages:
            try:
                decoded = ITCHDecoder.decode_message(msg_bytes)
                audit = self.book.step(decoded.event)
                records.append(audit)
                applied_count += 1
            except Exception as e:
                self.state = RecoveryState.INVALID
                self.book.is_valid = False
                return PacketProcessResult(
                    success=False,
                    state=self.state,
                    expected_sequence=self.expected_seq,
                    applied_messages=applied_count,
                    gap_detected=None,
                    error_message=f"Failed to decode message: {e}",
                    audit_records=tuple(records),
                )

        self.expected_seq += packet.message_count

        # Drain buffered packets if contiguous
        while self.expected_seq in self._buffer:
            buffered_pkt = self._buffer.pop(self.expected_seq)
            for msg_bytes in buffered_pkt.messages:
                decoded = ITCHDecoder.decode_message(msg_bytes)
                audit = self.book.step(decoded.event)
                records.append(audit)
                applied_count += 1
            self.expected_seq += buffered_pkt.message_count

        # If buffer is clear, restore SEQUENCED state and book validity
        if len(self._buffer) == 0:
            self.state = RecoveryState.SEQUENCED
            self.book.is_valid = True
        else:
            self.state = RecoveryState.RECOVERING

        return PacketProcessResult(
            success=True,
            state=self.state,
            expected_sequence=self.expected_seq,
            applied_messages=applied_count,
            gap_detected=None,
            error_message=None,
            audit_records=tuple(records),
        )
