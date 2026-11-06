unit TestSpecialTypes;

interface

uses
  DUnitX.TestFramework,
  Windows,
  SysUtils,
  System.UITypes,
  Classes,
  DateUtils,
  encoding.json;

type
  [TestFixture]
  TSpecialTypesTest = class
  public
    [Test] procedure TestDecodeDateTime;
    [Test] procedure TestDateAndTimeAreDates;
    [Test] procedure TestDateAndTimeAreCutOnDecode;
    [Test] procedure TestCurrencyIsWrittenExactly;
    [Test] procedure TestEncodeGUID;
    [Test] procedure TestDecodeGUID;
    [Test] procedure TestColorUsesWebHex;
    [Test] procedure TestColorRejectsWhatIsNotAWebColour;
  end;

implementation

{ TSpecialTypesTest }

procedure TSpecialTypesTest.TestDecodeDateTime;
var
  gotResult: TJSONResult;
  wantDateTime: TDateTime;
  gotDateTime: TDateTime;
  someDateTime: string;
begin
  // held as UTC by default, so the value is the wire's
  someDateTime:= '"2024-06-09T12:30:45.123Z"';
  wantDateTime:= EncodeDateTime(2024,6,9,12,30,45,123);

  gotResult:= JSON.Unmarshal(someDateTime,gotDateTime);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(wantDateTime,gotDateTime);
end;


type
  TDateAndTime = record
    Day: TDate;
    Clock: TTime;
  end;

// TDate and TTime are types of their own (type TDateTime), so they need their
// own registration - without it they went out as bare floats
procedure TSpecialTypesTest.TestDateAndTimeAreDates;
var
  r,got: TDateAndTime;
  s: string;
begin
  r.Day:= EncodeDate(2024,6,9);
  r.Clock:= EncodeTime(12,30,45,0);

  Assert.AreEqual(JSONOK,JSON.Marshal(r,s));
  Assert.AreEqual('{"Day":"2024-06-09T00:00:00.000Z","Clock":"1899-12-30T12:30:45.000Z"}',s,false);

  got:= Default(TDateAndTime);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(s,got));
  Assert.AreEqual(double(r.Day),double(got.Day));
  Assert.AreEqual(double(r.Clock),double(got.Clock),1/MSecsPerDay);
end;

// a full timestamp decodes into a TDate as its date and into a TTime as its
// time of day - cut after the conversion into the zone the value is held in
procedure TSpecialTypesTest.TestDateAndTimeAreCutOnDecode;
var
  got: TDateAndTime;
  c: TJSONConfig;
  j: TJSONCodec;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"Day":"2024-06-09T12:30:45Z","Clock":"2024-06-09T12:30:45Z"}',got));
  Assert.AreEqual(double(EncodeDate(2024,6,9)),double(got.Day));
  Assert.AreEqual(double(EncodeTime(12,30,45,0)),double(got.Clock),1/MSecsPerDay);

  // held as local time: the cut happens after the conversion to local
  c:= JSONDefaultConfig;
  c.DateTimeIsUTC:= false;
  j:= TJSONCodec.Create(c);
  try
    var instant:= TTimeZone.Local.ToUniversalTime(EncodeDateTime(2024,6,9,0,30,0,0));
    var text:= '{"Day":"'+DateToISO8601(instant)+'","Clock":"'+DateToISO8601(instant)+'"}';
    Assert.AreEqual(JSONOK,j.Unmarshal(text,got));
    Assert.AreEqual(double(EncodeDate(2024,6,9)),double(got.Day),'the local day');
    Assert.AreEqual(double(EncodeTime(0,30,0,0)),double(got.Clock),1/MSecsPerDay,'the local time of day');
  finally
    j.Free;
  end;
end;

type
  TMoney = record
    Amount: Currency;
    Boxed: Variant;
  end;

// a Currency is written from its scaled integer, not through a float: past
// fifteen significant digits FloatToStr rounded it
procedure TSpecialTypesTest.TestCurrencyIsWrittenExactly;
var
  m,got: TMoney;
  s: string;
begin
  m.Amount:= StrToCurr('123456789012.3456',TFormatSettings.Invariant);
  m.Boxed:= m.Amount;

  Assert.AreEqual(JSONOK,JSON.Marshal(m,s));
  Assert.AreEqual('{"Amount":123456789012.3456,"Boxed":123456789012.3456}',s,false);

  got:= Default(TMoney);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(s,got));
  Assert.IsTrue(got.Amount = m.Amount,'round-trips exactly');

  m.Amount:= -0.5;
  Assert.AreEqual(JSONOK,JSON.Marshal(m.Amount,s));
  Assert.AreEqual('-0.5',s,false);
end;

// encoding a TDateTime, as UTC and as local time, is covered by TestConfig

// lower case on the way out, as RFC 4122 asks
procedure TSpecialTypesTest.TestEncodeGUID;
var
  gotResult: TJSONResult;
  someGUID: TGUID;
  gotJSON: string;
begin
  someGUID:= StringToGUID('{e0c119de-4bdf-418f-ac93-4f150d72e1b0}');

  gotResult:= JSON.Marshal(someGUID,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('"e0c119de-4bdf-418f-ac93-4f150d72e1b0"',gotJSON);
end;

procedure TSpecialTypesTest.TestDecodeGUID;
var
  gotResult: TJSONResult;
  someGUID: string;
  gotGUID: TGUID;
  wantGUID: TGUID;
begin
  someGUID:= '"e0c119de-4bdf-418f-ac93-4f150d72e1b0"';
  wantGUID:= StringToGUID('{e0c119de-4bdf-418f-ac93-4f150d72e1b0}');

  gotResult:= JSON.Unmarshal(someGUID,gotGUID);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(wantGUID,gotGUID);

  // any case on the way in
  gotGUID:= Default(TGUID);
  gotResult:= JSON.Unmarshal(UpperCase(someGUID),gotGUID);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(wantGUID,gotGUID);
end;

// TColor is $00BBGGRR: the byte swap makes "#rrggbb" mean the same outside Delphi
procedure TSpecialTypesTest.TestColorUsesWebHex;
var
  someColour: TColor;
  gotColour: TColor;
  gotJSON: string;
begin
  // pure red is $000000FF in Delphi and #ff0000 everywhere else
  someColour:= TColors.Red;
  Assert.AreEqual(JSONOK,JSON.Marshal(someColour,gotJSON));
  Assert.AreEqual('"#ff0000"',gotJSON,'red');

  // ...and pure blue is the other end of the same swap
  someColour:= TColors.Blue;
  Assert.AreEqual(JSONOK,JSON.Marshal(someColour,gotJSON));
  Assert.AreEqual('"#0000ff"',gotJSON,'blue');

  // a value with three different bytes catches a swap that only looks right
  // on symmetric colours
  someColour:= TColor($123456);
  Assert.AreEqual(JSONOK,JSON.Marshal(someColour,gotJSON));
  Assert.AreEqual('"#563412"',gotJSON,'red $56, green $34, blue $12');

  gotColour:= 0;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,gotColour));
  Assert.IsTrue(gotColour = someColour,'and back again');

  // uppercase hex is still hex
  gotColour:= 0;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(string('"#AABBCC"'),gotColour));
  Assert.IsTrue(gotColour = TColor($00CCBBAA),'uppercase');
end;

// a system colour cannot be written either - that is a documented gotcha, pinned
// in TestGotchas
procedure TSpecialTypesTest.TestColorRejectsWhatIsNotAWebColour;
var
  gotColour: TColor;
begin
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(string('"#GGGGGG"'),gotColour),'not hex');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(string('"123456"'),gotColour),'no leading hash');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(string('"#12345"'),gotColour),'too short');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(string('"#1234567"'),gotColour),'too long');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(string('16711680'),gotColour),'a bare number');
end;

initialization
  TDUnitX.RegisterTestFixture(TSpecialTypesTest);

end.




