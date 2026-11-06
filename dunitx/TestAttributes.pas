unit TestAttributes;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAttributeTest = class
  public
    [Test] procedure TestSkip;
    [Test] procedure TestRename;
    [Test] procedure TestEncodeOmitEmpty;
  end;

implementation

uses
  System.Variants,
  encoding.json,
  TestHelpers;

type
  TRecordWithSkipAttr = record
    SomeString: string;
    [JSON('-')] SomeSkippedString: string;
  end;

  TRecordWithRenaming = record
    SomeString: string;
    [JSON('renamed_field')] RenamedField: string;
  end;

  TOmitEnum = (oeFirst, oeSecond);

  TRecordWithOmitEmpty = record
    [JSON('',true)] AString: string;
    [JSON('',true)] AnInt: integer;
    [JSON('',true)] AFloat: double;
    [JSON('',true)] AVariant: Variant;
    [JSON('',true)] ABool: boolean;
    [JSON('',true)] AnEnum: TOmitEnum;
  end;

// a skipped member is neither written nor read: the document may name it, and
// the destination keeps what it held
procedure TAttributeTest.TestSkip;
var
  r: TRecordWithSkipAttr;
begin
  r.SomeString:= 'a string';
  r.SomeSkippedString:= 'kept';
  Check.Encodes<TRecordWithSkipAttr>(r,'{"SomeString":"a string"}');

  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"SomeString":"this and that","SomeSkippedString":"ignored"}',r));
  Assert.AreEqual('this and that',r.SomeString);
  Assert.AreEqual('kept',r.SomeSkippedString);
end;

procedure TAttributeTest.TestRename;
var
  r: TRecordWithRenaming;
begin
  r.SomeString:= 'a string';
  r.RenamedField:= 'renamed';
  Check.RoundTrips<TRecordWithRenaming>(r,'{"SomeString":"a string","renamed_field":"renamed"}');
end;

procedure TAttributeTest.TestEncodeOmitEmpty;
var
  r: TRecordWithOmitEmpty;
begin
  r.AString:= 'a string';
  r.AnInt:= 123;
  r.AFloat:= 3.1415;
  r.AVariant:= 'variant!';
  r.ABool:= true;
  r.AnEnum:= oeSecond;
  Check.Encodes<TRecordWithOmitEmpty>(r,
    '{"AString":"a string","AnInt":123,"AFloat":3.1415,"AVariant":"variant!","ABool":true,"AnEnum":"oeSecond"}');

  // false is empty, as in Go. an enumeration's first member is not: it is a
  // value like any other, so it stays
  r.AString:= '';
  r.AnInt:= 0;
  r.AFloat:= 0.0;
  r.AVariant:= Unassigned;
  r.ABool:= false;
  r.AnEnum:= oeFirst;
  Check.Encodes<TRecordWithOmitEmpty>(r,'{"AnEnum":"oeFirst"}','empty');

  // a Null variant is empty too, not only an unassigned one
  r.AVariant:= System.Variants.Null;
  Check.Encodes<TRecordWithOmitEmpty>(r,'{"AnEnum":"oeFirst"}','null variant');
end;

initialization
  TDUnitX.RegisterTestFixture(TAttributeTest);

end.
