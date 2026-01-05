module rlp.encode;

import std.bigint : BigInt;
private import std.bitmanip : nativeToBigEndian;
private import std.exception : enforce;
private import std.traits : Unqual;

private import rlp : ctlz;
import rlp.exception : NegativeBigIntException;
import rlp.header;

/// Detect whether a type `T` can be encoded via RLP.
template isRlpEncodable(T)
{
    static if (
        is(T == bool) || is(T == ubyte) || is(T == ushort) || is(T == uint) ||
        is(T == ulong) || is(T == string) || is(T == BigInt)
    )
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
ubyte[] encode(T)(T value) pure @safe
    if (isRlpEncodable!T)
{
    ubyte[] buffer;
    buffer.reserve(T.sizeof);
    value.encode(buffer);
    return buffer;
}

/// Ditto.
ubyte[] encode(bool isList = false)(ubyte[] value) pure @safe
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
        size_t len = T.sizeof - (value.ctlz!true() / 8);
        buffer ~= cast(ubyte) (rlp.EMPTY_STRING_CODE + len);
        buffer.length += len;
        buffer[($ - len) .. $] = nativeToBigEndian(value)[($ - len) .. $];
    }
}

size_t encodeLength(T)(T value) @nogc nothrow pure @safe
if (is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong))
{
    return value < rlp.EMPTY_STRING_CODE
        ? 1
        : 1 + T.sizeof - (value.ctlz!true() / 8);
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

void encode(BigInt value, ref ubyte[] buffer) pure @safe
{
    enforce!NegativeBigIntException(value >= 0, "value must be larger than zero.");
    if (value.ulongLength() == 1)
    {
        encode!ulong(cast(ulong) value, buffer);
        return;
    }
    // encode as bytes.
    immutable ulong digit = value.getDigit(value.ulongLength() - 1);
    immutable idx = ulong.sizeof - (digit.ctlz!true() / 8);
    immutable payloadLen = idx + (value.ulongLength() - 1) * 8;
    Header h = { isList: false, payloadLen: payloadLen };
    h.encodeHeader(buffer);
    // first digit.
    buffer.length += idx;
    buffer[($ - idx) .. $] = nativeToBigEndian(digit)[($ - idx) .. $];
    // rest.
    foreach_reverse (i; 0 .. value.ulongLength() - 1)
    {
        buffer.length += ulong.sizeof;
        buffer[($ - ulong.sizeof) .. $] = nativeToBigEndian(value.getDigit(i));
    }
}

size_t encodeLength(BigInt value) pure @safe
{
    enforce!NegativeBigIntException(value >= 0, "value must be larger than zero.");
    if (value.ulongLength == 1)
        return encodeLength(cast(ulong) value);
    immutable ulong digit = value.getDigit(value.ulongLength() - 1);
    return 1 + ulong.sizeof - (digit.ctlz!true() / 8) + (value.ulongLength() - 1) * 8;
}

@("rlp encode - BigInt")
pure @safe unittest
{
    import std.digest : toHexString;
    import std.exception : assertThrown;

    assert(encode(BigInt("0")).toHexString == "80");
    assert(encode(BigInt("1")).toHexString == "01");
    assert(encode(BigInt("0x7F")).toHexString == "7F");
    assert(encode(BigInt("0x80")).toHexString == "8180");
    assert(encode(BigInt("0x400")).toHexString == "820400");
    assert(encode(BigInt("0xFFCCB5")).toHexString == "83FFCCB5");
    assert(encode(BigInt("0xFFCCB5DD")).toHexString == "84FFCCB5DD");
    assert(encode(BigInt("0xFFCCB5DDFF")).toHexString == "85FFCCB5DDFF");
    assert(encode(BigInt("0xFFCCB5DDFFEE")).toHexString == "86FFCCB5DDFFEE");
    assert(encode(BigInt("0xFFCCB5DDFFEE14")).toHexString == "87FFCCB5DDFFEE14");
    assert(encode(BigInt("0xFFCCB5DDFFEE1483")).toHexString == "88FFCCB5DDFFEE1483");

    assert(
        encode(BigInt("0x102030405060708090A0B0C0D0E0F2"))
            .toHexString == "8F102030405060708090A0B0C0D0E0F2"
    );
    assert(
		encode(BigInt("0x100020003000400050006000700080009000A000B000C000D000E01"))
            .toHexString == "9C0100020003000400050006000700080009000A000B000C000D000E01"
    );
    assert(
		encode(BigInt("0x10000000000000000000000000000000000000000000000000000000000000000"))
            .toHexString == "A1010000000000000000000000000000000000000000000000000000000000000000"
    );

    assertThrown!NegativeBigIntException(encode(BigInt("-1")));
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

size_t encodeLength(bool asList = false, T)(T[] value) @nogc pure @safe
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

size_t encodeLength(string value) @nogc pure @trusted
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

void encode(T : U[], U)(T values, ref ubyte[] buffer) pure @safe
    if (!is(Unqual!U == ubyte))
{
    rlpListHeader(values).encodeHeader(buffer);
    foreach (value; values)
        value.encode(buffer);
}

size_t encodeLength(T : U[], U)(T values) pure @safe
    if (!is(Unqual!U == ubyte))
{
    auto payloadLen = rlpListHeader(values).payloadLen;
    return payloadLen + lengthOfPayloadLength(payloadLen);
}

size_t lengthOfPayloadLength(size_t payloadLen) @nogc pure @safe
{
    return payloadLen < 56
        ? 1
        : 1 + size_t.sizeof - (payloadLen.ctlz!true() / 8);
}

Header rlpListHeader(T : U[], U)(T values) pure @safe
{
    Header h = { isList: true, payloadLen: 0 };
    foreach (v; values)
        h.payloadLen += v.encodeLength();
    return h;
}

@("rlp encode - list")
pure @safe unittest
{
    import std.digest : toHexString;

    assert(encode(new ulong[0]).toHexString == "C0");
    assert(encode!true([ubyte(0x0)]).toHexString == "C180");
    assert(encode([BigInt("0")]).toHexString == "C180");
    const ubyte[] magnitude = [1, 0, 0, 0, 0, 0, 0, 0, 0];
    assert(encode([BigInt(false, magnitude)]).toHexString == "CA89010000000000000000");
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
