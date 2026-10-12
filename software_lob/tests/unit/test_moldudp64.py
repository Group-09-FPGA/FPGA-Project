"""Unit tests for MoldUDP64 packet serialization, parsing, and framing."""

import pytest
from lob_sim.feed_decoder import ITCHDecoder
from lob_sim.models import Side
from lob_sim.moldudp64 import MoldUDP64Parser


def test_serialize_and_parse_moldudp64_packet():
    msg1 = ITCHDecoder.encode_add_order(
        order_id=1, side=Side.BUY, quantity=10, price=1000000
    )
    msg2 = ITCHDecoder.encode_add_order(
        order_id=2, side=Side.SELL, quantity=20, price=1020000
    )

    packet_bytes = MoldUDP64Parser.serialize_packet(
        session="SESSION01",
        sequence_number=100,
        messages=[msg1, msg2],
    )

    assert len(packet_bytes) == 20 + (2 + len(msg1)) + (2 + len(msg2))

    parsed = MoldUDP64Parser.parse_packet(packet_bytes)
    assert parsed.session == "SESSION01"
    assert parsed.sequence_number == 100
    assert parsed.message_count == 2
    assert len(parsed.messages) == 2
    assert parsed.messages[0] == msg1
    assert parsed.messages[1] == msg2
    assert not parsed.is_heartbeat
    assert not parsed.is_end_of_session


def test_heartbeat_packet():
    hb_bytes = MoldUDP64Parser.serialize_heartbeat(
        session="SESSION01", next_expected_seq=150
    )
    assert len(hb_bytes) == 20
    parsed = MoldUDP64Parser.parse_packet(hb_bytes)
    assert parsed.session == "SESSION01"
    assert parsed.sequence_number == 150
    assert parsed.message_count == 0
    assert parsed.is_heartbeat
    assert len(parsed.messages) == 0


def test_truncated_packet():
    with pytest.raises(ValueError, match="shorter than MoldUDP64 header size"):
        MoldUDP64Parser.parse_packet(b"SHORT_PACKET")
