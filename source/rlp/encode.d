module rlp.encode;

private import std.traits : Unqual;

private import rlp : ctlz;
import rlp.header;

/// Detect whether a type `T` can be encoded via RLP.
template isRlpEncodable(T)
{
    static if (is(T == bool) || is(T == ubyte) || is(T == ushort) ||
        is(T == uint) || is(T == ulong) || is(T == string))
    {
        enum isRlpEncodable = true;
    }
    else static if (is(T : U[], U))
    {
        enum isRlpEncodable = isRlpEncodable!U;
    }
    else
    {
        enum isRlpEncodable = false;
    }
}

/// Encode a value.
ubyte[] encode(T)(T value) nothrow pure @safe
    if (isRlpEncodable!T)
{
    ubyte[] buffer;
    buffer.reserve(T.sizeof);
    value.encode(buffer);
    return buffer;
}

/// Ditto.
ubyte[] encode(bool isList = false)(ubyte[] value) nothrow pure @safe
{
    ubyte[] buffer;
    buffer.reserve(value.length);
    value.encode!isList(buffer);
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

        ubyte[T.sizeof] be;
        size_t index = 0;
        be[].write!(T, Endian.bigEndian)(value, &index);
        size_t len = index - (value.ctlz!true() / 8);
        buffer ~= cast(ubyte) (rlp.EMPTY_STRING_CODE + len);
        buffer ~= be[(value.ctlz!true() / 8) .. index];
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
        return 1 + T.sizeof - (value.ctlz!true() / 8);
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

void encode(bool asList = false, T)(T[] value, ref ubyte[] buffer) nothrow pure @safe
    if (is(Unqual!T == ubyte))
{
    static if (asList)
    {
        rlpListHeader(value).encodeHeader(buffer);
        foreach (elem; value)
            elem.encode(buffer);
    }
    else
    {
        if (value.length != 1 || value[0] >= rlp.EMPTY_STRING_CODE)
        {
            Header h = { isList: false, payloadLen: value.length };
            h.encodeHeader(buffer);
        }
        buffer ~= value;
    }
}

size_t encodeLength(bool asList = false, T)(T[] value) @nogc nothrow pure @safe
    if (is(Unqual!T == ubyte))
{
    static if (asList)
    {
        auto payloadLen = rlpListHeader(value).payloadLength;
        return payloadLen + lengthOfPayloadLength(payloadLen);
    }
    else
    {
        size_t len = value.length;
        if (len != 1 || value[0] >= rlp.EMPTY_STRING_CODE)
        {
            len += lengthOfPayloadLength(len);
        }
        return len;
    }
}

@("rlp encode - bytes")
@safe unittest
{
    import std.digest : toHexString;
    import std.string : representation;

    assert(encode("".representation.dup).toHexString == "80");
    assert(encode([ubyte(0x7B)]).toHexString == "7B");
    assert(encode([ubyte(0x80)]).toHexString == "8180");
    assert(encode([ubyte(0xAB), ubyte(0XBA)]).toHexString == "82ABBA");
}


void encode(string value, ref ubyte[] buffer) nothrow pure @trusted
{
    encode!false(cast(ubyte[]) value, buffer);
}

size_t encodeLength(string value) @nogc nothrow pure @trusted
{
    return encodeLength!false(cast(ubyte[]) value);
}

@("rlp encode - string")
pure @safe unittest
{
    import std.digest : toHexString;

    assert(encode("").toHexString == "80");
    assert(encode("{").toHexString == "7B");
    assert(encode("test str").toHexString == "887465737420737472");
}

void encode(T : U[], U)(T values, ref ubyte[] buffer) nothrow pure @safe
    if (!is(Unqual!U == ubyte))
{
    rlpListHeader(values).encodeHeader(buffer);
    foreach (value; values)
        value.encode(buffer);
}

size_t encodeLength(T : U[], U)(T values) nothrow pure @safe
    if (!is(Unqual!U == ubyte))
{
    auto payloadLen = rlpListHeader(values).payloadLen;
    return payloadLen + lengthOfPayloadLength(payloadLen);
}

size_t lengthOfPayloadLength(size_t payloadLen) @nogc nothrow pure @safe
{
    return payloadLen < 56
        ? 1
        : 1 + size_t.sizeof - (payloadLen.ctlz!true() / 8);
}

Header rlpListHeader(T : U[], U)(T values) @nogc nothrow pure @safe
{
    Header h = { isList: true, payloadLen: 0 };
    foreach (v; values)
        h.payloadLen += v.encodeLength;
    return h;
}

@("rlp encode - list")
pure @safe unittest
{
    import std.digest : toHexString;

    assert(encode(new ulong[0]).toHexString == "C0");
    assert(encode!true([ubyte(0x0)]).toHexString == "C180");
    assert(encode([0xFFCCB5UL, 0xFFC0B5UL]).toHexString == "C883FFCCB583FFC0B5");
}

// tests from deth.
pure @trusted unittest
{
    import std.digest : toHexString;

    assert(encode([
        "cat", "dog", "dogg\0y", "man"
    ]).toHexString == "D38363617483646F6786646F67670079836D616E");
    assert(encode([
            "ccatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatat",
            "dog"
        ]).toHexString == "F84BB845636361746361746361746361746361746361746361746361746361746"
        ~ "36174636174636174636174636174636174636174636174636174636174636174636174636174617483646F67");
    assert(encode(["cat", ""]).toHexString == "C58363617480");
    auto d = cast(ubyte[][])[[1], [2, 3, 4], [123, 255]];
    assert(encode(d).toHexString == "C80183020304827BFF");    
}
