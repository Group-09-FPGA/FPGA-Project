"""MoldUDP64 downstream packet framing, parser, and serializer."""

from __future__ import annotations

import struct
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class MoldUDP64Packet:
    """A decoded MoldUDP64 downstream packet."""

    session: str
    sequence_number: int
    message_count: int
    messages: tuple[bytes, ...]

    @property
    def is_heartbeat(self) -> bool:
        """True if packet is a heartbeat (Message Count == 0)."""
        return self.message_count == 0

    @property
    def is_end_of_session(self) -> bool:
        """True if packet marks End of Session (Message Count == 0xFFFF)."""
        return self.message_count == 0xFFFF


class MoldUDP64Parser:
    """Parser and serializer for MoldUDP64 protocol downstream packets."""

    HEADER_SIZE = 20
    HEARTBEAT_COUNT = 0
    END_OF_SESSION_COUNT = 0xFFFF

    @classmethod
    def parse_packet(cls, data: bytes) -> MoldUDP64Packet:
        """Parse a MoldUDP64 binary packet from raw network bytes."""
        if len(data) < cls.HEADER_SIZE:
            raise ValueError(
                f"Packet length {len(data)} is shorter than MoldUDP64 header size {cls.HEADER_SIZE}"
            )

        session_raw, seq_num, msg_count = struct.unpack_from(
            ">10sQH", data, 0
        )
        session = session_raw.decode("ascii", errors="replace").strip()

        # Handle Heartbeat or End of Session
        if (
            msg_count == cls.HEARTBEAT_COUNT
            or msg_count == cls.END_OF_SESSION_COUNT
        ):
            return MoldUDP64Packet(
                session=session,
                sequence_number=seq_num,
                message_count=msg_count,
                messages=(),
            )

        offset = cls.HEADER_SIZE
        messages: list[bytes] = []

        for _ in range(msg_count):
            if offset + 2 > len(data):
                raise ValueError("Truncated MoldUDP64 packet: missing message length field")
            msg_len = struct.unpack_from(">H", data, offset)[0]
            offset += 2

            if offset + msg_len > len(data):
                raise ValueError(
                    f"Truncated MoldUDP64 packet: expected {msg_len} bytes, only {len(data) - offset} remaining"
                )

            msg_payload = data[offset : offset + msg_len]
            messages.append(msg_payload)
            offset += msg_len

        return MoldUDP64Packet(
            session=session,
            sequence_number=seq_num,
            message_count=msg_count,
            messages=tuple(messages),
        )

    @classmethod
    def serialize_packet(
        cls,
        session: str,
        sequence_number: int,
        messages: list[bytes],
    ) -> bytes:
        """Serialize payload messages into a MoldUDP64 downstream packet."""
        session_bytes = session.ljust(10)[:10].encode("ascii")
        msg_count = len(messages)
        header = struct.pack(">10sQH", session_bytes, sequence_number, msg_count)

        payload_parts = [header]
        for msg in messages:
            payload_parts.append(struct.pack(">H", len(msg)))
            payload_parts.append(msg)

        return b"".join(payload_parts)

    @classmethod
    def serialize_heartbeat(
        cls, session: str, next_expected_seq: int
    ) -> bytes:
        """Serialize a MoldUDP64 Heartbeat packet."""
        session_bytes = session.ljust(10)[:10].encode("ascii")
        return struct.pack(">10sQH", session_bytes, next_expected_seq, cls.HEARTBEAT_COUNT)
