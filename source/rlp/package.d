module rlp;

private import std.traits : Unqual;

public import rlp.decode;
public import rlp.encode;
public import rlp.exception;
public import rlp.header : Header;

package enum ubyte EMPTY_STRING_CODE = 0x80;
package enum ubyte EMPTY_LIST_CODE = 0xC0;


package size_t ctlz(bool isZeroUndef = false, T)(T value) @nogc nothrow pure @safe
    if (is(Unqual!T == ubyte) || is(Unqual!T == ushort) || is(Unqual!T == uint) ||
        is(Unqual!T == ulong) || is(Unqual!T == size_t))
{
    version(LDC)
    {
        pragma(LDC_allow_inline);
        import ldc.intrinsics : llvm_ctlz;
        return llvm_ctlz(value, isZeroUndef);
    }
    else
    {
        pragma(inline, true);
        import core.bitop : bsr;
        if (value == 0)
            return T.sizeof * 8;
        return (T.sizeof * 8 - 1) - bsr(value);
    }
}
