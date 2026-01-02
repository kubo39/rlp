module rlp.header;

private import std.bitmanip : read, write;
private import std.exception : enforce;
private import std.range : empty, popFrontExactly;

private import rlp : ctlz;
import rlp.exception;

/// RLP Header.
struct Header
{
    /// whether list or not.
    bool isList;
    /// Length of the payload in bytes.
    size_t payloadLength;
}

package:

void encodeHeader(Header header, ref ubyte[] buffer) pure nothrow @trusted
{
    if (header.payloadLength < 56)
    {
        const code = header.isList ? rlp.EMPTY_LIST_CODE : rlp.EMPTY_STRING_CODE;
        buffer ~= cast(ubyte) (code + header.payloadLength);
    }
    else
    {
        import std.system : Endian;

        auto be = new ubyte[size_t.sizeof];
        size_t index = 0;
        be.write!(size_t, Endian.bigEndian)(header.payloadLength, &index);
        size_t len = index - (header.payloadLength.ctlz!true() / 8);
        const code = header.isList ? 0xF7 : 0xB7;
        buffer ~= cast(ubyte) (code + len);
        buffer ~= be[(header.payloadLength.ctlz!true() / 8) .. index];
    }
}

struct DecodedHeader
{
    size_t offset;
    size_t payloadLen;
    bool isList;
}

void decodeHeader(ref DecodedHeader header, ref const(ubyte)[] input) @trusted
{
    enforce!InputIsNull(input.length > 0, "RLP header size is zero.");

    const prefix = input[0];
    switch (prefix)
    {
    case 0: .. case 0x7F:
        header.payloadLen = 1;
        break;
    case 0x80: .. case 0xB7:
        input.read!ubyte;
        header.offset = 1;
        header.payloadLen = prefix - 0x80;
        break;
    case 0xB8: .. case 0xBF:
    case 0xF8: .. case 0xFF:
        input.read!ubyte;
        header.isList = prefix >= 0xF8;
        const code = header.isList ? 0xF7 : 0xB7;
        const lenOfPayloadLen = prefix - code;
        input.popFrontExactly(lenOfPayloadLen);

        auto buffer = new ubyte[size_t.sizeof];
        // copy payloadLen to buffer.
        buffer[($ - lenOfPayloadLen) .. $] = input[0 .. lenOfPayloadLen];
        header.payloadLen = cast(size_t) buffer.read!ulong;
        assert(buffer.empty);
        header.offset = 1 + lenOfPayloadLen;
        break;
    case 0xC0: .. case 0xF7:
        input.read!ubyte;
        header.offset = 1;
        header.isList = true;
        header.payloadLen = prefix - 0xC0;
        break;
    default:
        assert(false, "unreachable");
    }

    enforce!InputTooShort(input.length >= header.payloadLen, "Too short payload was given.");
}
