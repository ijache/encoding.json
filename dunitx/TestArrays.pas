unit TestArrays;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArraysTest = class
  public
    [Test] procedure TestDynamicArraysRoundTrip;
    [Test] procedure TestStaticArrayRoundTrips;
  end;

implementation

uses
  TestHelpers;

type
  TSomeRecord = record
    IntValue: integer;
    StringValue: string;
  end;

  TFourInts = array[0..3] of integer;

procedure TArraysTest.TestDynamicArraysRoundTrip;
var
  records: TArray<TSomeRecord>;
begin
  // eighteen, so decoding grows the array past its initial capacity of 16
  Check.RoundTrips<TArray<integer>>([0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17],
    '[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17]','integers');
  Check.RoundTrips<TArray<string>>(['Paul','Ringo','George','John'],
    '["Paul","Ringo","George","John"]','strings');
  Check.RoundTrips<TArray<integer>>(nil,'[]','empty');

  SetLength(records,4);
  records[0].IntValue:= 1; records[0].StringValue:= 'Paul';
  records[1].IntValue:= 2; records[1].StringValue:= 'Ringo';
  records[2].IntValue:= 3; records[2].StringValue:= 'George';
  records[3].IntValue:= 4; records[3].StringValue:= 'John';
  Check.RoundTrips<TArray<TSomeRecord>>(records,
    '[{"IntValue":1,"StringValue":"Paul"},{"IntValue":2,"StringValue":"Ringo"},'+
    '{"IntValue":3,"StringValue":"George"},{"IntValue":4,"StringValue":"John"}]','records');
end;

// the exact-length rule for decoding is a documented gotcha, pinned in TestGotchas
procedure TArraysTest.TestStaticArrayRoundTrips;
var
  four: TFourInts;
begin
  four[0]:= 3; four[1]:= 1; four[2]:= 4; four[3]:= 1;
  Check.RoundTrips<TFourInts>(four,'[3,1,4,1]');
end;

initialization
  TDUnitX.RegisterTestFixture(TArraysTest);

end.
