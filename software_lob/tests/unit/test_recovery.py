"""Unit tests for MoldUDP64Receiver sequence tracking and recovery state machine."""

from lob_sim.feed_decoder import ITCHDecoder
from lob_sim.models import RecoveryState, Side
from lob_sim.moldudp64 import MoldUDP64Parser
from lob_sim.order_book import OrderBook
from lob_sim.recovery import MoldUDP64Receiver


def test_in_order_packet_processing():
    book = OrderBook()
    receiver = MoldUDP64Receiver(book, initial_seq=1)

    msg1 = ITCHDecoder.encode_add_order(
        order_id=1, side=Side.BUY, quantity=50, price=1000000
    )
    pkt1 = MoldUDP64Parser.serialize_packet("SESS1", 1, [msg1])

    res = receiver.process_raw_packet(pkt1)
    assert res.success
    assert res.state == RecoveryState.SEQUENCED
    assert res.expected_sequence == 2
    assert res.applied_messages == 1
    assert book.order_count == 1
    assert book.is_valid


def test_sequence_gap_detection_and_recovery():
    book = OrderBook()
    receiver = MoldUDP64Receiver(book, initial_seq=1)

    msg1 = ITCHDecoder.encode_add_order(
        order_id=1, side=Side.BUY, quantity=50, price=1000000
    )
    msg2 = ITCHDecoder.encode_add_order(
        order_id=2, side=Side.SELL, quantity=30, price=1020000
    )

    pkt1 = MoldUDP64Parser.serialize_packet("SESS1", 1, [msg1])
    pkt2 = MoldUDP64Parser.serialize_packet("SESS1", 2, [msg2])

    # 1. Packet 2 arrives BEFORE packet 1 (Gap detected!)
    res_gap = receiver.process_raw_packet(pkt2)
    assert not res_gap.success
    assert res_gap.state == RecoveryState.GAP_DETECTED
    assert res_gap.gap_detected == (1, 1)
    assert not book.is_valid
    assert receiver.buffered_packet_count == 1
    assert book.order_count == 0  # Not applied yet!

    # 2. Missing packet 1 arrives -> recovery applies packet 1 then buffered packet 2
    res_recovery = receiver.process_raw_packet(pkt1)
    assert res_recovery.success
    assert res_recovery.state == RecoveryState.SEQUENCED
    assert res_recovery.applied_messages == 2  # Both 1 and 2 applied!
    assert receiver.buffered_packet_count == 0
    assert receiver.expected_seq == 3
    assert book.order_count == 2
    assert book.is_valid


def test_duplicate_packet_ignored():
    book = OrderBook()
    receiver = MoldUDP64Receiver(book, initial_seq=1)

    msg1 = ITCHDecoder.encode_add_order(
        order_id=1, side=Side.BUY, quantity=50, price=1000000
    )
    pkt1 = MoldUDP64Parser.serialize_packet("SESS1", 1, [msg1])

    res1 = receiver.process_raw_packet(pkt1)
    assert res1.success
    assert res1.applied_messages == 1

    # Send pkt1 again
    res2 = receiver.process_raw_packet(pkt1)
    assert res2.success
    assert res2.applied_messages == 0  # Harmlessly ignored
    assert book.order_count == 1
