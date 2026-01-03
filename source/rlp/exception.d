module rlp.exception;

private import std.exception : basicExceptionCtors;

///
class InputIsNull : Exception
{
    mixin basicExceptionCtors;
}

///
class InputTooShort : Exception
{
    mixin basicExceptionCtors;
}

///
class InvalidInput : Exception
{
    mixin basicExceptionCtors;
}

///
class UnexpectedList : Exception
{
    mixin basicExceptionCtors;
}
