USING: arrays combinators crypto.common kernel io
io.encodings.binary io.files io.streams.byte-array math.vectors
strings sequences namespaces math parser sequences vectors
io.binary hashtables symbols ;
IN: crypto.sha1

! Implemented according to RFC 3174.

SYMBOLS: h0 h1 h2 h3 h4 A B C D E w K ;

: get-wth ( n -- wth ) w get nth ; inline
: shift-wth ( n -- x ) get-wth 1 bitroll-32 ; inline

: initialize-sha1 ( -- )
    0 bytes-read set
    HEX: 67452301 dup h0 set A set
    HEX: efcdab89 dup h1 set B set
    HEX: 98badcfe dup h2 set C set
    HEX: 10325476 dup h3 set D set
    HEX: c3d2e1f0 dup h4 set E set
    [
        20 HEX: 5a827999 <array> %
        20 HEX: 6ed9eba1 <array> %
        20 HEX: 8f1bbcdc <array> %
        20 HEX: ca62c1d6 <array> %
    ] { } make K set ;

! W(t) = S^1(W(t-3) XOR W(t-8) XOR W(t-14) XOR W(t-16))
: sha1-W ( t -- W_t )
     dup 3 - get-wth
     over 8 - get-wth bitxor
     over 14 - get-wth bitxor
     swap 16 - get-wth bitxor 1 bitroll-32 ;

! f(t;B,C,D) = (B AND C) OR ((NOT B) AND D)         ( 0 <= t <= 19)
! f(t;B,C,D) = B XOR C XOR D                        (20 <= t <= 39)
! f(t;B,C,D) = (B AND C) OR (B AND D) OR (C AND D)  (40 <= t <= 59)
! f(t;B,C,D) = B XOR C XOR D                        (60 <= t <= 79)
: sha1-f ( B C D t -- f_tbcd )
    20 /i
    {   
        { 0 [ >r over bitnot r> bitand >r bitand r> bitor ] }
        { 1 [ bitxor bitxor ] }
        { 2 [ 2dup bitand >r pick bitand >r bitand r> r> bitor bitor ] }
        { 3 [ bitxor bitxor ] }
    } case ;

: make-w ( str -- )
    #! compute w, steps a-b of RFC 3174, section 6.1
    16 [ nth-int-be w get push ] with each
    16 80 dup <slice> [ sha1-W w get push ] each ;

: init-letters ( -- )
    ! step c of RFC 3174, section 6.1
    h0 get A set
    h1 get B set
    h2 get C set
    h3 get D set
    h4 get E set ;

: inner-loop ( n -- temp )
    ! TEMP = S^5(A) + f(t;B,C,D) + E + W(t) + K(t);
    [
        [ B get C get D get ] keep sha1-f ,
        dup get-wth ,
        K get nth ,
        A get 5 bitroll-32 ,
        E get ,
    ] { } make sum >32-bit ; inline

: set-vars ( temp -- )
    ! E = D;  D = C;  C = S^30(B);  B = A; A = TEMP;
    D get E set
    C get D set
    B get 30 bitroll-32 C set
    A get B set
    A set ;

: calculate-letters ( -- )
    ! step d of RFC 3174, section 6.1
    80 [ inner-loop set-vars ] each ;

: update-hs ( -- )
    ! step e of RFC 3174, section 6.1
    A h0 update-old-new
    B h1 update-old-new
    C h2 update-old-new
    D h3 update-old-new
    E h4 update-old-new ;

: (process-sha1-block) ( str -- )
    80 <vector> w set make-w init-letters calculate-letters update-hs ;

: process-sha1-block ( str -- )
    dup length [ bytes-read [ + ] change ] keep 64 = [
        (process-sha1-block)
    ] [
        t bytes-read get pad-last-block
        [ (process-sha1-block) ] each
    ] if ;

: (stream>sha1) ( -- )
    64 read [ process-sha1-block ] keep
    length 64 = [ (stream>sha1) ] when ;

: get-sha1 ( -- str )
    [ [ h0 h1 h2 h3 h4 ] [ get 4 >be % ] each ] "" make ;

: stream>sha1 ( stream -- sha1 )
    [ initialize-sha1 (stream>sha1) get-sha1 ] with-stream ;

: byte-array>sha1 ( string -- sha1 )
    binary <byte-reader> stream>sha1 ;

: byte-array>sha1str ( string -- str )
    byte-array>sha1 hex-string ;

: byte-array>sha1-bignum ( string -- n )
    byte-array>sha1 be> ;

: file>sha1 ( file -- sha1 )
    binary <file-reader> stream>sha1 ;

: byte-array>sha1-interleave ( string -- seq )
    [ zero? ] left-trim
    dup length odd? [ 1 tail ] when
    seq>2seq [ byte-array>sha1 ] bi@
    swap 2seq>seq ;
