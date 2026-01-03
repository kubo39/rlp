module rlp.decode;

private import std.bitmanip : read;
private import std.exception : enforce;
private import std.range : empty, popFrontExactly;

private import rlp.header;
private import rlp.exception;

/// Decode a value.
T decode(T)(ref const(ubyte)[] input) @trusted
{
    static if (is(T == bool))
    {
        enforce!InputTooShort(input.length >= 1, "A bool must be one byte.");
        switch (input[0])
        {
        case 0x80:
            return false;
        case 0x1:
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
        assert(header.payloadLen <= T.sizeof);

        if (header.payloadLen == 0)
            return 0;

        auto buffer = new ubyte[T.sizeof];
        buffer[($ - header.payloadLen) .. $] = input[0 .. header.payloadLen];
        T n = buffer.read!T;
        assert(buffer.empty);
        input.popFrontExactly(header.payloadLen);
        return n;
    }
    else static if (is(T == string))
    {
        Header header = {
            isList: false,
            payloadLen: 0,
        };
        decodeHeader(header, input);
        enforce!UnexpectedList(!header.isList, "Expected string, got a list instead.");
        return cast(T) input[0 ..  header.payloadLen];
    }
    else static if (is(T == ubyte[]))
    {
        Header header = {
            isList: true,
            payloadLen: 0,
        };
        decodeHeader(header, input);
        assert(header.isList);
        return input[0 .. header.payloadLen].dup;
    }
    else static if (is(T U == U[]))
    {
        static if (is(U == ushort) || is(U == uint) || is(U == ulong) || is(U == string))
        {
            Header header = {
                isList: true,
                payloadLen: 0,
            };

            decodeHeader(header, input);
            assert(header.isList);

            if (input.length == 0)
                return [];

            T answer;

            while (input.length)
            {
                U elem = decode!U(input);
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
