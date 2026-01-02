module rlp.encode;

private import ldc.intrinsics : llvm_ctlz;

import rlp.header;

enum isRlpEncodable(T) =
    is(T == bool) || is(T == ubyte) || is(T == ushort) ||
    is(T == uint) || is(T == ulong);
enum isRlpEncodable(T : U[], U) = isRlpEncodable!U;

/// Encode a value.
ubyte[] encode(T)(T value) nothrow pure @safe
    if (isRlpEncodable!T)
{
    ubyte[] buffer;
    buffer.reserve(T.sizeof);
    value.encode(buffer);
    return buffer;
}

private:

void encode(bool value, ref ubyte[] buffer) nothrow pure @safe
{
    buffer ~= value ? 1 : rlp.EMPTY_STRING_CODE;
}

size_t encodeLength(bool _) @nogc nothrow pure @safe
{
    return 1;
}

@("rlp encode - bool")
pure @safe unittest
{
    import std.digest : toHexString;

    assert(encode(true).toHexString == "01");
    assert(encode(false).toHexString == "80");
}

void encode(T)(T value, ref ubyte[] buffer) nothrow pure @trusted
if (is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong))
{
    if (value == 0)
    {
        buffer ~= rlp.EMPTY_STRING_CODE;
    }
    else if (value < cast(T) rlp.EMPTY_STRING_CODE)
    {
        buffer ~= cast(ubyte) value;
    }
    else
    {
        import std.bitmanip : write;
        import std.system : Endian;

        auto be = new ubyte[T.sizeof];
        size_t index = 0;
        be.write!(T, Endian.bigEndian)(value, &index);
        size_t len = index - (value.llvm_ctlz(true) / 8);
        buffer ~= cast(ubyte) (rlp.EMPTY_STRING_CODE + len);
        buffer ~= be[(value.llvm_ctlz(true) / 8) .. index];
    }
}

size_t encodeLength(T)(T value) @nogc nothrow pure @safe
if (is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong))
{
    if (value < rlp.EMPTY_STRING_CODE)
    {
        return 1;
    }
    else
    {
        return 1 + T.sizeof - (value.llvm_ctlz(true) / 8);
    }
}

@("rlp encode - unsinged integers")
pure @safe unittest
{
    import std.digest : toHexString;

    assert(encode((ubyte(0))).toHexString == "80");
    assert(encode((ubyte(1))).toHexString == "01");
    assert(encode((ubyte(0x7F))).toHexString == "7F");
    assert(encode((ubyte(0x80))).toHexString == "8180");

    assert(encode((ushort(0))).toHexString == "80");
    assert(encode((ushort(1))).toHexString == "01");
    assert(encode((ushort(0x7F))).toHexString == "7F");
    assert(encode((ushort(0x80))).toHexString == "8180");
    assert(encode((ushort(0x400))).toHexString == "820400");

    assert(encode((uint(0))).toHexString == "80");
    assert(encode((uint(1))).toHexString == "01");
    assert(encode((uint(0x7F))).toHexString == "7F");
    assert(encode((uint(0x80))).toHexString == "8180");
    assert(encode((uint(0x400))).toHexString == "820400");
    assert(encode((uint(0xFFCCB5))).toHexString == "83FFCCB5");
    assert(encode((uint(0xFFCCB5DD))).toHexString == "84FFCCB5DD");

    assert(encode((ulong(0))).toHexString == "80");
    assert(encode((ulong(1))).toHexString == "01");
    assert(encode((ulong(0x7F))).toHexString == "7F");
    assert(encode((ulong(0x80))).toHexString == "8180");
    assert(encode((ulong(0x400))).toHexString == "820400");
    assert(encode((ulong(0xFFCCB5))).toHexString == "83FFCCB5");
    assert(encode((ulong(0xFFCCB5DD))).toHexString == "84FFCCB5DD");
    assert(encode((ulong(0xFFCCB5DDFF))).toHexString == "85FFCCB5DDFF");
    assert(encode((ulong(0xFFCCB5DDFFEE))).toHexString == "86FFCCB5DDFFEE");
    assert(encode((ulong(0xFFCCB5DDFFEE14))).toHexString == "87FFCCB5DDFFEE14");
    assert(encode((ulong(0xFFCCB5DDFFEE1483))).toHexString == "88FFCCB5DDFFEE1483");
}

void encode(T : U[], U)(T values, ref ubyte[] buffer) nothrow pure @safe
{
    rlpListHeader(values).encodeHeader(buffer);
    foreach (value; values)
        value.encode(buffer);
}

Header rlpListHeader(T : U[], U)(T values) @nogc nothrow pure @safe
{
    Header h = { isList: true, payloadLength: 0 };
    foreach (v; values)
        h.payloadLength += v.encodeLength;
    return h;
}

@("rlp encode - list")
pure @safe unittest
{
    import std.digest : toHexString;

    assert(encode(new ulong[0]).toHexString == "C0");
    assert(encode([ubyte(0)]).toHexString == "C180");
    assert(encode([0xFFCCB5UL, 0xFFC0B5UL]).toHexString == "C883FFCCB583FFC0B5");
}
