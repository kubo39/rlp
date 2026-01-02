module rlp;

public import rlp.decode;
public import rlp.encode;
public import rlp.exception;
public import rlp.header : Header;

package enum ubyte EMPTY_STRING_CODE = 0x80;
package enum ubyte EMPTY_LIST_CODE = 0xC0;
