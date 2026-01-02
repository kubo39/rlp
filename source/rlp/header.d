module rlp.header;

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
        import std.bitmanip : write;
        import std.system : Endian;
        import ldc.intrinsics;

        auto be = new ubyte[size_t.sizeof];
        size_t index = 0;
        be.write!(size_t, Endian.bigEndian)(header.payloadLength, &index);
        size_t len = index - (header.payloadLength.llvm_ctlz(true) / 8);
        const code = header.isList ? 0xF7 : 0xB7;
        buffer ~= cast(ubyte) (code + len);
        buffer ~= be[(header.payloadLength.llvm_ctlz(true) / 8) .. index];
    }
}
