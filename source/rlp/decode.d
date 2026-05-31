module rlp.decode;

import std.bigint : BigInt;
private import std.bitmanip : read;
private import std.exception : enforce;
private import std.range : empty, popFront, popFrontExactly;
private import std.system : Endian;

private import rlp.header;
private import rlp.exception;

/// Detect whether a type `T` can be decoded from RLP.
template isRlpDecodable(T)
{
    static if (is(T == bool) || is(T == ubyte) || is(T == ushort) ||
        is(T == uint) || is(T == ulong) || is(T == string) ||
        is(T == BigInt))
    {
        enum isRlpDecodable = true;
    }
    else static if (is(T : U[], U))
    {
        enum isRlpDecodable = isRlpDecodable!U;
    }
    else
    {
        enum isRlpDecodable = false;
    }
}

/// Decode a value.
T decode(T)(ref const(ubyte)[] input) @safe
    if (isRlpDecodable!T)
{
    static if (is(T == bool))
    {
        enforce!InputTooShort(input.length >= 1, "A bool must be one byte.");
        switch (input[0])
        {
        case 0x80:
            input.popFront;
            return false;
        case 0x1:
            input.popFront;
            return true;
        default:
            throw new InvalidInput("An invalid bool value.");
        }
    }
    else static if (is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong))
    {
        Header header = {
            isList: false,
            payloadLen: 0,
        };
        decodeHeader(header, input);
        enforce!UnexpectedList(!header.isList, "Expected " ~T.stringof ~ " got a list instead.");
        enforce!InvalidInput(header.payloadLen <= T.sizeof,
            "Payload too large for " ~ T.stringof ~ ".");

        if (header.payloadLen == 0)
            return 0;

        auto buffer = new ubyte[T.sizeof];
        buffer[($ - header.payloadLen) .. $] = input[0 .. header.payloadLen];
        T n = buffer.read!(T, Endian.bigEndian);
        assert(buffer.empty);
        input.popFrontExactly(header.payloadLen);
        return n;
    }
    else static if (is(T == BigInt))
    {
        Header header = {
            isList: false,
            payloadLen: 0,
        };
        decodeHeader(header, input);
        enforce!UnexpectedList(!header.isList, "Expected BigInt, got a list instead.");

        auto result = BigInt(false, input[0 .. header.payloadLen]);
        input.popFrontExactly(header.payloadLen);
        return result;
    }
    else static if (is(T == string))
    {
        import std.string : assumeUTF;
        Header header = {
            isList: false,
            payloadLen: 0,
        };
        decodeHeader(header, input);
        enforce!UnexpectedList(!header.isList, "Expected string, got a list instead.");
        string ret = input[0 ..  header.payloadLen].assumeUTF();
        input.popFrontExactly(header.payloadLen);
        return ret;
    }
    else static if (is(T == ubyte[]))
    {
        Header header = {
            isList: true,
            payloadLen: 0,
        };
        decodeHeader(header, input);
        enforce!UnexpectedString(header.isList, "Expected a list, got a byte string instead.");
        auto ret = input[0 .. header.payloadLen].dup;
        input.popFrontExactly(header.payloadLen);
        return ret;
    }
    else static if (is(T U == U[]))
    {
        static if (is(U == ushort) || is(U == uint) || is(U == ulong) || is(U == string) || is(U == BigInt))
        {
            Header header = {
                isList: true,
                payloadLen: 0,
            };

            decodeHeader(header, input);
            enforce!UnexpectedString(header.isList, "Expected a list, got a byte string instead.");

            // Only the list payload belongs to this list; consume exactly that
            // much from input and decode elements within those bytes. Reading
            // until input is empty would swallow trailing data and break nested
            // lists.
            auto payload = input[0 .. header.payloadLen];
            input.popFrontExactly(header.payloadLen);

            T answer;
            while (payload.length)
            {
                U elem = decode!U(payload);
                answer ~= elem;
            }
            return answer;
        }
    }
    else static assert(false, "Unsupported type: " ~ T.stringof);
}

version(unittest)
{
    struct TestCase(T)
    {
        const(ubyte)[] input;
        T expected;
        bool isError;
    }
}

@("rlp decode - bool")
@safe unittest
{
    foreach (tc; [
        TestCase!bool([0x80], false),
        TestCase!bool([0x01], true),
        TestCase!bool([0x09], false, true)
    ])
    {
        if (!tc.isError)
            assert(decode!bool(tc.input) == tc.expected);
        else
        {
            import std.exception : assertThrown;
            assertThrown(decode!bool(tc.input) == tc.expected);
        }
    }
}

@("rlp decode - ubyte")
@safe unittest
{
    foreach (tc; [
        TestCase!ubyte([0x80], 0),
        TestCase!ubyte([0x01], 1),
        TestCase!ubyte([0x82], 0, true)
    ])
    {
        if (!tc.isError)
            assert(decode!ubyte(tc.input) == tc.expected);
        else
        {
            import std.exception : assertThrown;
            assertThrown(decode!ubyte(tc.input) == tc.expected);
        }
    }
}

@("rlp decode - ulong")
@safe unittest
{
    foreach (tc; [
        TestCase!ulong([0x80], 0),
        TestCase!ulong([0x09], 9),
        TestCase!ulong([0x82, 0x05, 0x05], 0x0505),
        TestCase!ulong([0xC0], 0, true),
        TestCase!ulong([0x82], 0, true)
    ])
    {
        if (!tc.isError)
            assert(decode!ulong(tc.input) == tc.expected);
        else
        {
            import std.exception : assertThrown;
            assertThrown(decode!ulong(tc.input) == tc.expected);
        }
    }
}

@("rlp decode - uint")
@safe unittest
{
    foreach (tc; [
        TestCase!uint([0x80], 0),
        TestCase!uint([0x09], 9)
    ])
    {
        assert(decode!uint(tc.input) == tc.expected);
    }
}

@("rlp decode - string")
@safe unittest
{
    foreach (tc; [
        TestCase!string([0x83, 'd', 'o', 'g'], "dog"),
        TestCase!string([0xC0], "", true),
        TestCase!string([0xC1], "", true),
        TestCase!string([0xD7], "", true)
    ])
    {
        if (!tc.isError)
            assert(decode!string(tc.input) == tc.expected);
        else
        {
            import std.exception : assertThrown;
            assertThrown(decode!string(tc.input));
        }
    }
}

@("rlp decode - ubyte[]")
@safe unittest
{
    foreach (tc; [
        TestCase!(ubyte[])([0xC0], []),
        TestCase!(ubyte[])([0xC3, 0x1, 0x2, 0x3], [0x1, 0x2, 0x3]),
        TestCase!(ubyte[])([0xC1], [], true),
        TestCase!(ubyte[])([0xD7], [], true)
    ])
    {
        if (!tc.isError)
            assert(decode!(ubyte[])(tc.input) == tc.expected);
        else
        {
            import std.exception : assertThrown;
            assertThrown(decode!(ubyte[])(tc.input));
        }
    }
}

@("rlp decode - uint[]")
@safe unittest
{
    foreach (tc; [
        TestCase!(uint[])([0xC0], []),
        TestCase!(uint[])([0xC1], [], true)
    ])
    {
        if (!tc.isError)
            assert(decode!(uint[])(tc.input) == tc.expected);
        else
        {
            import std.exception : assertThrown;
            assertThrown(decode!(uint[])(tc.input));
        }
    }
}

@("rlp decode - ulong[]")
@safe unittest
{
    foreach (tc; [
        TestCase!(ulong[])([0xC0], []),
        TestCase!(ulong[])(
            [0xC8,
             0x83, 0xBB, 0xCC, 0xB5,
             0x83, 0xFF, 0xC0, 0xB5
            ], [0xBBCCB5, 0xFFC0B5]),
        TestCase!(ulong[])([0xD7], [], true)
    ])
    {
        if (!tc.isError)
            assert(decode!(ulong[])(tc.input) == tc.expected);
        else
        {
            import std.exception : assertThrown;
            assertThrown(decode!(ulong[])(tc.input));
        }
    }
}

@("rlp decode - BigInt")
@safe unittest
{
    foreach (tc; [
        TestCase!BigInt([0x80], BigInt(0)),
        TestCase!BigInt([0x01], BigInt(1)),
        TestCase!BigInt([0x7F], BigInt(0x7F)),
        TestCase!BigInt([0x81, 0x80], BigInt(0x80)),
        TestCase!BigInt([0x82, 0x04, 0x00], BigInt(0x400)),
        TestCase!BigInt([0x83, 0xFF, 0xCC, 0xB5], BigInt(0xFFCCB5)),
        TestCase!BigInt([0xC0], BigInt(0), true),
    ])
    {
        if (!tc.isError)
            assert(decode!BigInt(tc.input) == tc.expected);
        else
        {
            import std.exception : assertThrown;
            assertThrown!UnexpectedList(decode!BigInt(tc.input));
        }
    }
}

@("rlp decode - BigInt[]")
@safe unittest
{
    foreach (tc; [
        TestCase!(BigInt[])([0xC0], []),
        TestCase!(BigInt[])([0xC1, 0x80], [BigInt(0)]),
        TestCase!(BigInt[])([0xC2, 0x01, 0x02], [BigInt(1), BigInt(2)]),
        TestCase!(BigInt[])(
            [0xC8,
             0x83, 0xFF, 0xCC, 0xB5,
             0x83, 0xFF, 0xC0, 0xB5
            ], [BigInt(0xFFCCB5), BigInt(0xFFC0B5)]),
        TestCase!(BigInt[])([0xD7], [], true),
    ])
    {
        if (!tc.isError)
            assert(decode!(BigInt[])(tc.input) == tc.expected);
        else
        {
            import std.exception : assertThrown;
            assertThrown(decode!(BigInt[])(tc.input));
        }
    }
}

@("rlp decode - long-form header (payload >= 56)")
@safe unittest
{
    import rlp.encode : encode;

    // Regression for the long-form header bug: payloads of 56 bytes or more
    // use a long-form header (prefix 0xB8..0xBF / 0xF8..0xFF) whose length
    // bytes must be read before being consumed. Short-form-only tests never
    // exercised this path.

    // string round-trip across the short/long boundary and beyond.
    foreach (n; [55, 56, 57, 70, 300, 1000])
    {
        string s;
        foreach (i; 0 .. n)
            s ~= cast(char) ('a' + (i % 26));
        const enc = encode(s);
        const(ubyte)[] input = enc;
        const decoded = decode!string(input);
        assert(decoded == s);
        assert(input.length == 0, "the whole input must be consumed");
    }

    // explicit byte-level check: "a" x 70 encodes to B8 46 [61 x70].
    {
        string s;
        foreach (i; 0 .. 70)
            s ~= "a";
        auto enc = encode(s);
        assert(enc[0] == 0xB8);
        assert(enc[1] == 70);
        const(ubyte)[] input = enc;
        Header header;
        decodeHeader(header, input);
        assert(!header.isList);
        assert(header.payloadLen == 70);
        assert(input[0] == 0x61, "input must point at the payload, not the length byte");
    }

    // long list round-trip (prefix 0xF8..): a list whose payload >= 56 bytes.
    {
        ulong[] values;
        foreach (i; 0 .. 20)
            values ~= 0xFFCCB5UL + i;
        const enc = encode(values);
        assert(enc[0] >= 0xF8, "expected a long-form list header");
        const(ubyte)[] input = enc;
        const decoded = decode!(ulong[])(input);
        assert(decoded == values);
        assert(input.length == 0);
    }
}

@("rlp decode - malformed input is rejected, even with -release")
@safe unittest
{
    import std.exception : assertThrown;

    // These guard against malformed/crafted input. They must be enforce(),
    // not assert(), so the checks survive a -release build instead of turning
    // into out-of-bounds reads.

    // long-form header claims more length bytes than the input has.
    {
        const(ubyte)[] input = [cast(ubyte) 0xBF];  // wants 8 length bytes, none follow
        assertThrown!InputTooShort(decode!string(input));
    }

    // integer payload larger than the target type.
    {
        // 0x89 => byte string of 9 bytes, which does not fit in a ulong (8).
        const(ubyte)[] input = [
            cast(ubyte) 0x89,
            1, 2, 3, 4, 5, 6, 7, 8, 9
        ];
        assertThrown!InvalidInput(decode!ulong(input));
    }

    // a list where an integer is expected.
    {
        const(ubyte)[] input = [cast(ubyte) 0xC1, 0x01];  // a list, not an integer
        assertThrown!UnexpectedList(decode!ulong(input));
    }
}

@("rlp decode - list consumes only its own payload")
@safe unittest
{
    // A list must consume exactly its payload, leaving any trailing bytes in
    // the input. Reading until input is empty would swallow them.
    {
        // [0xC2, 0x01, 0x02] is the list [1, 2]; 0x03 is unrelated trailing data.
        const(ubyte)[] input = [cast(ubyte) 0xC2, 0x01, 0x02, 0x03];
        const decoded = decode!(ulong[])(input);
        assert(decoded == [1, 2]);
        assert(input == [cast(ubyte) 0x03], "trailing byte must remain");
    }

    // Two lists concatenated: decode the first, the second stays in input.
    {
        const(ubyte)[] input = [
            cast(ubyte) 0xC2, 0x01, 0x02,   // [1, 2]
            cast(ubyte) 0xC1, 0x03          // [3]
        ];
        const first = decode!(ulong[])(input);
        assert(first == [1, 2]);
        assert(input == [cast(ubyte) 0xC1, 0x03]);
        const second = decode!(ulong[])(input);
        assert(second == [3]);
        assert(input.length == 0);
    }
}
