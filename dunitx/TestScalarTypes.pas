unit TestScalarTypes;

// Every ordinal width, string kind and float kind, both ways - the Store*/Load*
// dispatch.

interface

uses
  DUnitX.TestFramework,
  encoding.json;

type
  TSomeEnum = (seFirst, seSecond, seThird);

  TIntegerWidths = record
    AShortInt: ShortInt;
    AByte: Byte;
    ASmallInt: SmallInt;
    AWord: Word;
    AInteger: Integer;
    ACardinal: Cardinal;
    AInt64: Int64;
  end;

  TFloatKinds = record
    ASingle: Single;
    ADouble: Double;
    AExtended: Extended;
    ACurrency: Currency;
  end;

  TStringKinds = record
    AString: string;
    AAnsiString: AnsiString;
    AUTF8String: UTF8String;
    AWideString: WideString;
    AShortString: ShortString;
  end;

  TCharKinds = record
    AChar: char;
    AAnsiChar: AnsiChar;
    AWideChar: WideChar;
  end;

  TUnsigned = record
    ACardinal: cardinal;
    AUInt64: UInt64;
  end;

  TBoolKinds = record
    ABoolean: Boolean;
    AByteBool: ByteBool;
    AWordBool: WordBool;
    ALongBool: LongBool;
  end;

  TEnumHolder = record
    AnEnum: TSomeEnum;
  end;

  [TestFixture]
  TScalarTypesTest = class
  public
    [Test] procedure TestIntegerWidthsAtBoundaries;
    [Test] procedure TestIntegerWidthsRoundtrip;
    [Test] procedure TestFloatKinds;
    [Test] procedure TestStringKinds;
    [Test] procedure TestBoolKinds;
    [Test] procedure TestNamedEnum;
    [Test] procedure TestCharKinds;
    [Test] procedure TestFullWidthUnsigned;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

// the interesting case: if the width-dispatch were wrong, an extreme value
// would either truncate or scribble over the neighbouring field
procedure TScalarTypesTest.TestIntegerWidthsAtBoundaries;
var
  someJSON: UTF8String;
  got: TIntegerWidths;
begin
  someJSON:= '{"AShortInt":-128,"AByte":255,"ASmallInt":-32768,"AWord":65535,'
           + '"AInteger":-2147483648,"ACardinal":4294967295,"AInt64":9223372036854775807}';

  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));
  Assert.AreEqual(ShortInt(-128),got.AShortInt,'ShortInt min');
  Assert.AreEqual(Byte(255),got.AByte,'Byte max');
  Assert.AreEqual(SmallInt(-32768),got.ASmallInt,'SmallInt min');
  Assert.AreEqual(Word(65535),got.AWord,'Word max');
  Assert.AreEqual(Integer(-2147483648),got.AInteger,'Integer min');
  Assert.AreEqual(Cardinal(4294967295),got.ACardinal,'Cardinal max');
  Assert.AreEqual(Int64(9223372036854775807),got.AInt64,'Int64 max');

  // the other end
  someJSON:= '{"AShortInt":127,"AByte":0,"ASmallInt":32767,"AWord":0,'
           + '"AInteger":2147483647,"ACardinal":0,"AInt64":-9223372036854775808}';

  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));
  Assert.AreEqual(ShortInt(127),got.AShortInt,'ShortInt max');
  Assert.AreEqual(Byte(0),got.AByte,'Byte min');
  Assert.AreEqual(SmallInt(32767),got.ASmallInt,'SmallInt max');
  Assert.AreEqual(Word(0),got.AWord,'Word min');
  Assert.AreEqual(Integer(2147483647),got.AInteger,'Integer max');
  Assert.AreEqual(Cardinal(0),got.ACardinal,'Cardinal min');
  Assert.AreEqual(Int64(-9223372036854775808),got.AInt64,'Int64 min');

  // set in reverse field order, all ones: a too-wide write only shows when the
  // narrow member is written after its neighbour. Keep the order
  someJSON:= '{"AInt64":-1,"ACardinal":4294967295,"AInteger":-1,'
           + '"AWord":65535,"ASmallInt":-1,"AByte":255,"AShortInt":-1}';

  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));
  Assert.AreEqual(ShortInt(-1),got.AShortInt,'ShortInt neighbour-safe');
  Assert.AreEqual(Byte(255),got.AByte,'Byte neighbour-safe');
  Assert.AreEqual(SmallInt(-1),got.ASmallInt,'SmallInt neighbour-safe');
  Assert.AreEqual(Word(65535),got.AWord,'Word neighbour-safe');
  Assert.AreEqual(Integer(-1),got.AInteger,'Integer neighbour-safe');
  Assert.AreEqual(Cardinal(4294967295),got.ACardinal,'Cardinal neighbour-safe');
  Assert.AreEqual(Int64(-1),got.AInt64,'Int64 neighbour-safe');
end;

procedure TScalarTypesTest.TestIntegerWidthsRoundtrip;
var
  want,got: TIntegerWidths;
  someJSON: UTF8String;
begin
  want.AShortInt:= -12;
  want.AByte:= 200;
  want.ASmallInt:= -3000;
  want.AWord:= 60000;
  want.AInteger:= -123456;
  want.ACardinal:= 4000000000;
  want.AInt64:= -1234567890123;

  Assert.AreEqual(JSONOK,JSON.Marshal(want,someJSON));
  Assert.AreEqual(UTF8String('{"AShortInt":-12,"AByte":200,"ASmallInt":-3000,"AWord":60000,'
    + '"AInteger":-123456,"ACardinal":4000000000,"AInt64":-1234567890123}'),someJSON);

  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));
  Assert.AreEqual(want.AShortInt,got.AShortInt);
  Assert.AreEqual(want.AByte,got.AByte);
  Assert.AreEqual(want.ASmallInt,got.ASmallInt);
  Assert.AreEqual(want.AWord,got.AWord);
  Assert.AreEqual(want.AInteger,got.AInteger);
  Assert.AreEqual(want.ACardinal,got.ACardinal);
  Assert.AreEqual(want.AInt64,got.AInt64);
end;

procedure TScalarTypesTest.TestFloatKinds;
var
  want,got: TFloatKinds;
  someJSON: UTF8String;
begin
  // values that are exactly representable, so the comparison is not about
  // float formatting
  want.ASingle:= 0.5;
  want.ADouble:= -1234.25;
  want.AExtended:= 2.75;
  want.ACurrency:= 1234.5678;

  Assert.AreEqual(JSONOK,JSON.Marshal(want,someJSON));
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));

  Assert.AreEqual(want.ASingle,got.ASingle,0.0,'Single');
  Assert.AreEqual(want.ADouble,got.ADouble,0.0,'Double');
  Assert.AreEqual(Double(want.AExtended),Double(got.AExtended),0.0,'Extended');
  Assert.AreEqual(want.ACurrency,got.ACurrency,'Currency');

  // MaxSingle's shortest text lies just above it and must read back
  want.ASingle:= MaxSingle;
  want.ADouble:= -MaxSingle;
  Assert.AreEqual(JSONOK,JSON.Marshal(want,someJSON));
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got),'the largest single');
  Assert.IsTrue(got.ASingle = MaxSingle,'...comes back as itself');

  // a Currency is read as a Currency, not through a float - which must not
  // cost it any number JSON can spell
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"ACurrency":1.5e2}'),got),'exponent notation');
  Assert.AreEqual(Currency(150),got.ACurrency);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"ACurrency":-0.0001}'),got),'the smallest step');
  Assert.AreEqual(Currency(-0.0001),got.ACurrency);
end;

procedure TScalarTypesTest.TestStringKinds;
var
  want,got: TStringKinds;
  someJSON: UTF8String;
begin
  // AnsiString is limited to whatever its declared codepage can represent,
  // so it only gets latin-1. the unicode-capable kinds get more.
  want.AString:= 'Grüße — こんにちは';
  want.AAnsiString:= 'Grüße';
  want.AUTF8String:= 'Grüße — こんにちは';
  want.AWideString:= 'Grüße — こんにちは';
  want.AShortString:= 'Grüße';

  Assert.AreEqual(JSONOK,JSON.Marshal(want,someJSON));
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));

  Assert.AreEqual(want.AString,got.AString,'string');
  Assert.AreEqual(want.AAnsiString,got.AAnsiString,'AnsiString');
  Assert.AreEqual(want.AUTF8String,got.AUTF8String,'UTF8String');
  Assert.AreEqual(want.AWideString,got.AWideString,'WideString');
  Assert.AreEqual(string(want.AShortString),string(got.AShortString),'ShortString');
end;

procedure TScalarTypesTest.TestBoolKinds;
var
  want,got: TBoolKinds;
  someJSON: UTF8String;
begin
  want.ABoolean:= true;
  want.AByteBool:= false;
  want.AWordBool:= true;
  want.ALongBool:= false;

  Assert.AreEqual(JSONOK,JSON.Marshal(want,someJSON));
  Assert.AreEqual(UTF8String('{"ABoolean":true,"AByteBool":false,"AWordBool":true,"ALongBool":false}'),someJSON);

  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));
  Assert.IsTrue(got.ABoolean,'Boolean');
  Assert.IsFalse(boolean(got.AByteBool),'ByteBool');
  Assert.IsTrue(boolean(got.AWordBool),'WordBool');
  Assert.IsFalse(boolean(got.ALongBool),'LongBool');
end;

// a named enum encodes as its delphi identifier
procedure TScalarTypesTest.TestNamedEnum;
var
  want,got: TEnumHolder;
  someJSON: UTF8String;
begin
  want.AnEnum:= seSecond;

  Assert.AreEqual(JSONOK,JSON.Marshal(want,someJSON));
  Assert.AreEqual(UTF8String('{"AnEnum":"seSecond"}'),someJSON);

  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));
  Assert.IsTrue(got.AnEnum = seSecond,'seSecond');

  someJSON:= '{"AnEnum":"seThird"}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));
  Assert.IsTrue(got.AnEnum = seThird,'seThird');

  // an identifier that does not belong to the type must be rejected. the
  // JSON is well-formed, so this is a mismatch and not a syntax error
  someJSON:= '{"AnEnum":"seNotAMember"}';
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(someJSON,got),'unknown member');
end;

// a char is one character of text; an AnsiChar holds less than a WideChar
procedure TScalarTypesTest.TestCharKinds;
var
  want,got: TCharKinds;
  someJSON: UTF8String;
  someWideChar: WideChar;
begin
  want.AChar:= 'A';
  want.AAnsiChar:= AnsiChar('b');
  want.AWideChar:= 'C';

  Assert.AreEqual(JSONOK,JSON.Marshal(want,someJSON));
  Assert.AreEqual(UTF8String('{"AChar":"A","AAnsiChar":"b","AWideChar":"C"}'),someJSON);

  got:= Default(TCharKinds);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));
  Assert.IsTrue(got.AChar = 'A','AChar');
  Assert.IsTrue(got.AAnsiChar = AnsiChar('b'),'AAnsiChar');
  Assert.IsTrue(got.AWideChar = 'C','AWideChar');

  // a char holds exactly one character, so anything else is a mismatch -
  // well-formed JSON that the destination cannot take
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('"AB"'),someWideChar),'two characters');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('""'),someWideChar),'no characters');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('67'),someWideChar),'a number is not a character');

  // non-ASCII fits a WideChar...
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('"' + UTF8String(#$00E4) + '"'),someWideChar));
  Assert.IsTrue(someWideChar = #$00E4,'a-umlaut into a WideChar');

  // ...and a character needing two UTF-16 units fits neither
  Assert.AreEqual(JSONTypeMismatch,
    JSON.Unmarshal(UTF8String('"' + UTF8String(#$D83D#$DE00) + '"'),someWideChar),
    'a character outside the BMP needs two code units');
end;


// RTTI reports their maximum as -1; High(UInt64) must not come out as "-1"
procedure TScalarTypesTest.TestFullWidthUnsigned;
var
  want,got: TUnsigned;
  someJSON: UTF8String;
begin
  want.ACardinal:= High(cardinal);
  want.AUInt64:= High(UInt64);

  Assert.AreEqual(JSONOK,JSON.Marshal(want,someJSON));
  Assert.AreEqual(UTF8String('{"ACardinal":4294967295,"AUInt64":18446744073709551615}'),someJSON);

  got:= Default(TUnsigned);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,got));
  Assert.IsTrue(got.ACardinal = High(cardinal),'cardinal round-trip');
  Assert.IsTrue(got.AUInt64 = High(UInt64),'UInt64 round-trip');

  // unsigned means unsigned in both directions
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('{"ACardinal":-1}'),got),'-1 into a cardinal');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('{"AUInt64":-1}'),got),'-1 into a UInt64');
end;


initialization
  TDUnitX.RegisterTestFixture(TScalarTypesTest);

end.
