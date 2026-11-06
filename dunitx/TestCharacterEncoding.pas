unit TestCharacterEncoding;

interface

uses
  System.SysUtils,
  System.Classes,
  Windows,
  DUnitX.TestFramework,
  encoding.json;

type
  [TestFixture]
  TCharacterEncodingTest = class
  public
    [Test] procedure TestEncodingUnicodeSucceeds;
    [Test] procedure TestEncodingUTF8Succeeds;
    [Test] procedure TestUntypedEntryPointsTakeBothStrings;
    [Test] procedure TestDecodeEscapeSequences;
    [Test] procedure TestDecodeUnicodeEscapes;
    [Test] procedure TestDecodeUnpairedSurrogates;
    [Test] procedure TestDecodeEscapedNull;
    [Test] procedure TestDecodeEscapeAfterLongText;
    [Test] procedure TestControlCharRoundtrip;
    [Test] procedure TestEncodeControlCharsAsUnicodeEscapes;
    [Test] procedure TestKeysAreEscaped;
    [Test] procedure TestKeyMatching;
  end;

implementation

{ TCharacterEncodingTest }

procedure TCharacterEncodingTest.TestEncodingUnicodeSucceeds;
var
  testString: UnicodeString;
  gotResult: TJSONResult;
  gotJSON: UnicodeString;
  wantJSON: UnicodeString;

begin
  testString:= 'Hällö Wëlt! ' + #9 + ' ' + #7 + ' Привет, мир! こんにちは世界!';
  wantJSON:= '"Hällö Wëlt! \t \u0007 Привет, мир! こんにちは世界!"';

  gotResult:= JSON.Marshal(testString,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(wantJSON,gotJSON);
end;

procedure TCharacterEncodingTest.TestEncodingUTF8Succeeds;
var
  testString: UnicodeString;
  gotResult: TJSONResult;

  gotJSON: UTF8String;
  wantJSON: UTF8String;
begin
  testString:= 'Hällö Wëlt! Привет, мир! こんにちは世界!';
  wantJSON:= '"Hällö Wëlt! Привет, мир! こんにちは世界!"';

  gotResult:= JSON.Marshal(testString,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(wantJSON,gotJSON);
end;

// Format and Parse are the entry points for a type known only at run time.
// Like Marshal and Unmarshal, they take a UTF8String and a UnicodeString alike
procedure TCharacterEncodingTest.TestUntypedEntryPointsTakeBothStrings;
var
  value,decoded: UnicodeString;
  utf8: UTF8String;
  unicode: UnicodeString;
begin
  value:= 'H'+#$E4+'ll'+#$F6+' '+#$20AC;

  Assert.AreEqual(JSONOK,JSON.Format(TypeInfo(UnicodeString),@value,'',utf8));
  Assert.AreEqual(UTF8String('"'+value+'"'),utf8,'into a UTF8String');
  Assert.AreEqual(JSONOK,JSON.Format(TypeInfo(UnicodeString),@value,'',unicode));
  Assert.AreEqual('"'+value+'"',unicode,'into a UnicodeString');

  decoded:= '';
  Assert.AreEqual(JSONOK,JSON.Parse(utf8,TypeInfo(UnicodeString),@decoded));
  Assert.AreEqual(value,decoded,'from a UTF8String');
  decoded:= '';
  Assert.AreEqual(JSONOK,JSON.Parse(unicode,TypeInfo(UnicodeString),@decoded));
  Assert.AreEqual(value,decoded,'from a UnicodeString');

  Assert.AreEqual(JSONSyntax,JSON.Parse(UTF8String(''),TypeInfo(UnicodeString),@decoded),'an empty document');
  Assert.AreEqual(JSONSyntax,JSON.Parse(UnicodeString(''),TypeInfo(UnicodeString),@decoded),'...in either string');
end;

// the two-character escapes must decode to the exact control-characters
// named by the JSON-spec (\f is #12 and \r is #13, not #11/#12)
procedure TCharacterEncodingTest.TestDecodeEscapeSequences;
var
  testJSON: UTF8String;
  gotResult: TJSONResult;
  gotValue: UnicodeString;
begin
  testJSON:= '"\b\t\n\f\r\"\\\/"';

  gotResult:= JSON.Unmarshal(testJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(UnicodeString(#8#9#10#12#13 + '"\/'),gotValue);
end;

// \uXXXX must be decoded to a code-point and re-encoded as UTF-8,
// including surrogate-pairs for anything beyond the BMP
procedure TCharacterEncodingTest.TestDecodeUnicodeEscapes;
var
  testJSON: UTF8String;
  gotResult: TJSONResult;
  gotValue: UnicodeString;
begin
  // 1-byte, 2-byte, 3-byte and (via surrogate-pair) 4-byte UTF-8
  testJSON:= '"\u0041\u00e9\u20ac\ud83d\ude00"';

  gotResult:= JSON.Unmarshal(testJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(UnicodeString('A' + #$00E9 + #$20AC + #$D83D + #$DE00),gotValue);

  // mixed with literal text
  testJSON:= '"caf\u00e9 \u2013 \u00fcber"';
  gotResult:= JSON.Unmarshal(testJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(UnicodeString('caf' + #$00E9 + ' ' + #$2013 + ' ' + #$00FC + 'ber'),gotValue);
end;

// unpaired surrogates are replaced by U+FFFD, a trailing escape that is
// not a low surrogate must still be decoded on its own
procedure TCharacterEncodingTest.TestDecodeUnpairedSurrogates;
var
  gotResult: TJSONResult;
  gotValue: UnicodeString;
  testJSON: UTF8String;
begin
  testJSON:= '"\ud800"';
  gotResult:= JSON.Unmarshal(testJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(UnicodeString(#$FFFD),gotValue);

  testJSON:= '"\udc00"';
  gotResult:= JSON.Unmarshal(testJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(UnicodeString(#$FFFD),gotValue);

  // high surrogate followed by a non-surrogate escape
  testJSON:= '"\ud800A"';
  gotResult:= JSON.Unmarshal(testJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(UnicodeString(#$FFFD + 'A'),gotValue);

  // inverted order
  testJSON:= '"\ude00\ud83d"';
  gotResult:= JSON.Unmarshal(testJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(UnicodeString(#$FFFD + #$FFFD),gotValue);
end;

// an escaped null is a valid character and must not truncate the value
procedure TCharacterEncodingTest.TestDecodeEscapedNull;
var
  gotResult: TJSONResult;
  gotValue: UnicodeString;
  testJSON: UTF8String;
begin
  testJSON:= '"a\u0000b"';

  gotResult:= JSON.Unmarshal(testJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(3,Length(gotValue));
  Assert.AreEqual(UnicodeString('a' + #0 + 'b'),gotValue);
end;

// at the first escape the text before it is copied out - more here than the
// scratch buffer starts with; the plain string after must not see it
procedure TCharacterEncodingTest.TestDecodeEscapeAfterLongText;
const
  LONG_TEXT = 'abcdefghijklmnopqrstuvwxyz0123456789';
var
  gotResult: TJSONResult;
  gotValue: TArray<UnicodeString>;
  testJSON: UTF8String;
begin
  testJSON:= '["' + LONG_TEXT + '\n' + LONG_TEXT + '","plain","","\t"]';

  gotResult:= JSON.Unmarshal(testJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(4,integer(Length(gotValue)));
  Assert.AreEqual(UnicodeString(LONG_TEXT + #10 + LONG_TEXT),gotValue[0]);
  Assert.AreEqual(UnicodeString('plain'),gotValue[1]);
  Assert.AreEqual(UnicodeString(''),gotValue[2]);
  Assert.AreEqual(UnicodeString(#9),gotValue[3]);
end;

// encoder and decoder must agree on the escape-table
procedure TCharacterEncodingTest.TestControlCharRoundtrip;
var
  testString: UnicodeString;
  gotJSON: UTF8String;
  gotResult: TJSONResult;
  gotValue: UnicodeString;
begin
  testString:= 'a' + #8 + 'b' + #9 + 'c' + #10 + 'd' + #12 + 'e' + #13 + 'f';

  gotResult:= JSON.Marshal(testString,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(UTF8String('"a\bb\tc\nd\fe\rf"'),gotJSON);

  gotResult:= JSON.Unmarshal(gotJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(testString,gotValue);
end;

// a control character without a short escape goes out as \u00XX, not dropped
procedure TCharacterEncodingTest.TestEncodeControlCharsAsUnicodeEscapes;
var
  testString: UnicodeString;
  gotJSON: UTF8String;
  gotResult: TJSONResult;
  gotValue: UnicodeString;
begin
  testString:= 'a' + #1 + 'b' + #7 + 'c' + #11 + 'd' + #27 + 'e' + #31 + 'f';

  gotResult:= JSON.Marshal(testString,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(UTF8String('"a\u0001b\u0007c\u000bd\u001be\u001ff"'),gotJSON);

  gotResult:= JSON.Unmarshal(gotJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(testString,gotValue);
end;

type TRecordWithAwkwardKeys = record
  [JSON('quote"inside')]        A: string;
  [JSON('back\slash')]          B: string;
  [JSON('tab' + #9 + 'inside')] C: string;
  [JSON('bell' + #7 + 'inside')] D: string;
end;

// a key needing escapes goes out escaped and is matched unescaped
procedure TCharacterEncodingTest.TestKeysAreEscaped;
var
  someRecord: TRecordWithAwkwardKeys;
  gotJSON: UTF8String;
  gotResult: TJSONResult;
  gotRecord: TRecordWithAwkwardKeys;
begin
  someRecord.A:= '1';
  someRecord.B:= '2';
  someRecord.C:= '3';
  someRecord.D:= '4';

  gotResult:= JSON.Marshal(someRecord,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(UTF8String('{"quote\"inside":"1","back\\slash":"2","tab\tinside":"3","bell\u0007inside":"4"}'),gotJSON);

  gotResult:= JSON.Unmarshal(gotJSON,gotRecord);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('1',gotRecord.A);
  Assert.AreEqual('2',gotRecord.B);
  Assert.AreEqual('3',gotRecord.C);
  Assert.AreEqual('4',gotRecord.D);
end;

// the member names are built from char-codes on purpose, so the source-encoding
// of this file cannot influence what is being tested
type TRecordWithNonASCIIKeys = record
  [JSON('stra' + #$00DF + 'e')] A: string;
  [JSON('M' + #$00DC + 'LLER')] B: string;
  [JSON('Title')]               C: string;
end;

// keys match on raw UTF-8 like CompareText: a..z fold, everything else exact
procedure TCharacterEncodingTest.TestKeyMatching;
var
  someRecord,gotRecord: TRecordWithNonASCIIKeys;
  gotJSON,someJSON: UTF8String;
begin
  someRecord.A:= '1';
  someRecord.B:= '2';
  someRecord.C:= '3';

  Assert.AreEqual(JSONOK,JSON.Marshal(someRecord,gotJSON));

  gotRecord:= default(TRecordWithNonASCIIKeys);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,gotRecord));
  Assert.AreEqual('1',gotRecord.A,'non-ascii key roundtrip');
  Assert.AreEqual('2',gotRecord.B,'non-ascii key roundtrip');
  Assert.AreEqual('3',gotRecord.C,'non-ascii key roundtrip');

  // ascii is folded, in both directions
  gotRecord:= default(TRecordWithNonASCIIKeys);
  someJSON:= '{"TITLE":"x","tItLe":"y"}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,gotRecord));
  Assert.AreEqual('y',gotRecord.C,'ascii case-insensitive');

  // non-ascii is not folded - CompareText never did either
  gotRecord:= default(TRecordWithNonASCIIKeys);
  someJSON:= UTF8String('{"m') + UTF8String(#$00FC) + UTF8String('ller":"x"}');
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,gotRecord));
  Assert.AreEqual('',gotRecord.B,'non-ascii case is not folded');

  // an escaped key is matched after unescaping, not before
  gotRecord:= default(TRecordWithNonASCIIKeys);
  someJSON:= UTF8String('{"stra') + UTF8String('\') + UTF8String('u00dfe":"z"}');
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,gotRecord));
  Assert.AreEqual('z',gotRecord.A,'escaped key matches unescaped name');

  // a name that is only a prefix of a member must not match it
  gotRecord:= default(TRecordWithNonASCIIKeys);
  someJSON:= '{"Titl":"no","Title":"yes"}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,gotRecord));
  Assert.AreEqual('yes',gotRecord.C,'prefix does not match');
end;

initialization
  TDUnitX.RegisterTestFixture(TCharacterEncodingTest);

end.
