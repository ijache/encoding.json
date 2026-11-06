unit TestConfig;

// TJSONConfig: what Create and Configure accept, and that each setting reaches the
// reader and writer. The date tests start from a known UTC instant, so no machine's
// time zone changes the expectations.

interface

uses
  DUnitX.TestFramework;

type
  TDepth3 = record
    V: integer;
  end;

  TDepth2 = record
    Inner: TDepth3;
  end;

  TDepth1 = record
    Inner: TDepth2;
  end;

  TSmall = record
    A: integer;
    B: string;
  end;

  [TestFixture]
  TConfigTest = class
  public
    [Test] procedure TestGlobalInstanceDefaults;
    [Test] procedure TestZeroConfigIsUsable;
    [Test] procedure TestIndentImpliesALineBreak;
    [Test] procedure TestMaxDepthFromConfigOnDecode;
    [Test] procedure TestMaxDepthFromConfigOnEncode;
    [Test] procedure TestLineBreakFromConfig;
    [Test] procedure TestConfigureTakesEffectOnALiveInstance;

    [Test] procedure TestRFC3339IsUTCByDefault;
    [Test] procedure TestDateTimeIsUTCByDefault;
    [Test] procedure TestWireIsAlwaysUTC;
    [Test] procedure TestOffsetTextStillRoundTrips;
    [Test] procedure TestEpochSeconds;
    [Test] procedure TestEpochMillis;
    [Test] procedure TestDecodeFollowsTheTokenNotTheConfig;
    [Test] procedure TestNumberUnitComesFromTheConfig;
    [Test] procedure TestVariantDateUsesTheSameFormat;
    [Test] procedure TestDateTimeRejectsALiteral;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Variants,
  encoding.json;

const
  // 2024-06-09T12:30:45.123Z by hand: 19883 days * 86400 + 45045 seconds
  EPOCH_SECONDS = 1717936245;
  EPOCH_MILLIS  = 1717936245123;
  RFC3339_TEXT  = '"2024-06-09T12:30:45.123Z"';

// the instant above as local time, for an instance built with ConfigWith
function TheInstant: TDateTime;
begin
  result:= TTimeZone.Local.ToLocalTime(EncodeDateTime(2024,6,9,12,30,45,123));
end;

// TDateTime held as local time, so the conversion is what gets tested
function ConfigWith(fmt: TJSONDateTimeFormat): TJSONConfig;
begin
  result:= JSONDefaultConfig;
  result.DateTimeIsUTC:= false;
  result.DateTimeFormat:= fmt;
end;

{ TConfigTest }

procedure TConfigTest.TestGlobalInstanceDefaults;
begin
  Assert.AreEqual(64,JSON.Config.MaxDepth,'MaxDepth');
  Assert.AreEqual(jdfRFC3339,JSON.Config.DateTimeFormat,'DateTimeFormat');
  Assert.AreEqual(#10,JSON.Config.LineBreak,'LineBreak');
end;

// Default(TJSONConfig) is all zeroes - MaxDepth 0 would mean "nothing can be
// encoded at all", so Configure lifts it to the default instead
procedure TConfigTest.TestZeroConfigIsUsable;
var
  j: TJSONCodec;
  s: UTF8String;
  r: TSmall;
begin
  j:= TJSONCodec.Create(Default(TJSONConfig));
  try
    Assert.AreEqual(JSON_DEFAULTMAXDEPTH,j.Config.MaxDepth,'MaxDepth');
    r.A:= 1; r.B:= 'b';
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual(UTF8String('{"A":1,"B":"b"}'),s);
  finally
    j.Free;
  end;
end;

// an indent without a line break would be one long line; Format supplies the
// default for this document only
procedure TConfigTest.TestIndentImpliesALineBreak;
var
  j: TJSONCodec;
  r: TSmall;
  s: string;
begin
  j:= TJSONCodec.Create(Default(TJSONConfig));   // LineBreak is '' here
  try
    r.A:= 1; r.B:= 'b';
    Assert.AreEqual(JSONOK,j.MarshalIndent(r,'  ',s));
    Assert.AreEqual('{'#10'  "A": 1,'#10'  "B": "b"'#10'}',s);
    Assert.AreEqual('',j.Config.LineBreak,'the instance config is left alone');
  finally
    j.Free;
  end;
end;

procedure TConfigTest.TestMaxDepthFromConfigOnDecode;
var
  cfg: TJSONConfig;
  j: TJSONCodec;
  got: TDepth1;
  someJSON: UTF8String;
begin
  someJSON:= '{"Inner":{"Inner":{"V":1}}}';

  cfg:= JSONDefaultConfig;
  cfg.MaxDepth:= 2;
  j:= TJSONCodec.Create(cfg);
  try
    Assert.AreEqual(JSONMaxDepthReached,j.Unmarshal(someJSON,got),'depth 2');
  finally
    j.Free;
  end;

  cfg.MaxDepth:= 3;
  j:= TJSONCodec.Create(cfg);
  try
    Assert.AreEqual(JSONOK,j.Unmarshal(someJSON,got),'depth 3');
    Assert.AreEqual(1,got.Inner.Inner.V);
  finally
    j.Free;
  end;
end;

procedure TConfigTest.TestMaxDepthFromConfigOnEncode;
var
  cfg: TJSONConfig;
  j: TJSONCodec;
  r: TDepth1;
  s: UTF8String;
begin
  r.Inner.Inner.V:= 1;

  cfg:= JSONDefaultConfig;
  cfg.MaxDepth:= 2;
  j:= TJSONCodec.Create(cfg);
  try
    Assert.AreEqual(JSONMaxDepthReached,j.Marshal(r,s),'depth 2');
  finally
    j.Free;
  end;

  cfg.MaxDepth:= 3;
  j:= TJSONCodec.Create(cfg);
  try
    Assert.AreEqual(JSONOK,j.Marshal(r,s),'depth 3');
    Assert.AreEqual(UTF8String('{"Inner":{"Inner":{"V":1}}}'),s);
  finally
    j.Free;
  end;
end;

procedure TConfigTest.TestLineBreakFromConfig;
var
  cfg: TJSONConfig;
  j: TJSONCodec;
  r: TSmall;
  s: string;
begin
  cfg:= JSONDefaultConfig;
  cfg.LineBreak:= #13#10;
  j:= TJSONCodec.Create(cfg);
  try
    r.A:= 1; r.B:= 'b';
    Assert.AreEqual(JSONOK,j.MarshalIndent(r,'  ',s));
    Assert.AreEqual('{'#13#10'  "A": 1,'#13#10'  "B": "b"'#13#10'}',s);
  finally
    j.Free;
  end;
end;

// config is read per call, never baked into a cached member
procedure TConfigTest.TestConfigureTakesEffectOnALiveInstance;
var
  cfg: TJSONConfig;
  j: TJSONCodec;
  r: TSmall;
  s: string;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    r.A:= 1; r.B:= 'b';
    Assert.AreEqual(JSONOK,j.MarshalIndent(r,' ',s));
    Assert.AreEqual('{'#10' "A": 1,'#10' "B": "b"'#10'}',s,'before');

    cfg:= JSONDefaultConfig;
    cfg.LineBreak:= #13#10;
    j.Configure(cfg);

    Assert.AreEqual(JSONOK,j.MarshalIndent(r,' ',s));
    Assert.AreEqual('{'#13#10' "A": 1,'#13#10' "B": "b"'#13#10'}',s,'after');
    Assert.AreEqual(#13#10,j.Config.LineBreak,'Config reads back');
  finally
    j.Free;
  end;
end;

procedure TConfigTest.TestRFC3339IsUTCByDefault;
var
  j: TJSONCodec;
  s: string;
  got: TDateTime;
begin
  j:= TJSONCodec.Create(ConfigWith(jdfRFC3339));
  try
    Assert.AreEqual(JSONOK,j.Marshal(TheInstant,s));
    Assert.AreEqual(RFC3339_TEXT,s);

    Assert.AreEqual(JSONOK,j.Unmarshal(s,got));
    Assert.AreEqual(double(TheInstant),double(got),1/MSecsPerDay);
  finally
    j.Free;
  end;
end;

// the default holds a TDateTime as UTC and converts nothing: the value is the
// wire's, in both directions and in every format
procedure TConfigTest.TestDateTimeIsUTCByDefault;
var
  j: TJSONCodec;
  c: TJSONConfig;
  utc,got: TDateTime;
  s: string;
begin
  utc:= EncodeDateTime(2024,6,9,12,30,45,123);
  Assert.IsTrue(JSONDefaultConfig.DateTimeIsUTC);

  Assert.AreEqual(JSONOK,JSON.Marshal(utc,s));
  Assert.AreEqual(RFC3339_TEXT,s,false);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(s,got));
  Assert.AreEqual(double(utc),double(got),1/MSecsPerDay);

  // an offset is honoured on the way in: the same instant, back as UTC
  Assert.AreEqual(JSONOK,JSON.Unmarshal('"2024-06-09T14:30:45.123+02:00"',got));
  Assert.AreEqual(double(utc),double(got),1/MSecsPerDay);

  // an epoch too
  c:= JSONDefaultConfig;
  c.DateTimeFormat:= jdfEpochMillis;
  j:= TJSONCodec.Create(c);
  try
    Assert.AreEqual(JSONOK,j.Marshal(utc,s));
    Assert.AreEqual(IntToStr(EPOCH_MILLIS),s);
    Assert.AreEqual(JSONOK,j.Unmarshal(s,got));
    Assert.AreEqual(double(utc),double(got),1/MSecsPerDay);
  finally
    j.Free;
  end;
end;

// built with SysUtils rather than ToISO8601, so it is not checking itself
procedure TConfigTest.TestWireIsAlwaysUTC;
var
  j: TJSONCodec;
  s: string;
  want: string;
begin
  j:= TJSONCodec.Create(ConfigWith(jdfRFC3339));
  try
    Assert.AreEqual(JSONOK,j.Marshal(TheInstant,s));
  finally
    j.Free;
  end;

  want:= System.SysUtils.FormatDateTime('yyyy-mm-dd"T"hh:nn:ss',
           TTimeZone.Local.ToUniversalTime(TheInstant));
  Assert.AreEqual('"'+want,Copy(s,1,Length(want)+1),'the wire carries UTC');
  Assert.AreEqual('Z"',Copy(s,Length(s)-1,2),'...and says so');
end;

// an explicit offset instead of Z decodes to the same instant
procedure TConfigTest.TestOffsetTextStillRoundTrips;
var
  j: TJSONCodec;
  s: string;
  got: TDateTime;
begin
  s:= '"'+TheInstant.ToISO8601(false)+'"';

  j:= TJSONCodec.Create(ConfigWith(jdfRFC3339));
  try
    Assert.AreEqual(JSONOK,j.Unmarshal(s,got));
    Assert.AreEqual(double(TheInstant),double(got),1/MSecsPerDay);
  finally
    j.Free;
  end;
end;

procedure TConfigTest.TestEpochSeconds;
var
  j: TJSONCodec;
  s: string;
  got: TDateTime;
begin
  j:= TJSONCodec.Create(ConfigWith(jdfEpoch));
  try
    Assert.AreEqual(JSONOK,j.Marshal(TheInstant,s));
    Assert.AreEqual(IntToStr(EPOCH_SECONDS),s);

    Assert.AreEqual(JSONOK,j.Unmarshal(s,got));
    // seconds, so the .123 is gone - that is the format's own resolution
    Assert.AreEqual(double(TheInstant),double(got),1/SecsPerDay);
  finally
    j.Free;
  end;
end;

procedure TConfigTest.TestEpochMillis;
var
  j: TJSONCodec;
  s: string;
  got: TDateTime;
begin
  j:= TJSONCodec.Create(ConfigWith(jdfEpochMillis));
  try
    Assert.AreEqual(JSONOK,j.Marshal(TheInstant,s));
    Assert.AreEqual(IntToStr(EPOCH_MILLIS),s);

    Assert.AreEqual(JSONOK,j.Unmarshal(s,got));
    Assert.AreEqual(double(TheInstant),double(got),1/MSecsPerDay);
  finally
    j.Free;
  end;
end;

// the token decides, not the config - or changing the setting would orphan old
// documents
procedure TConfigTest.TestDecodeFollowsTheTokenNotTheConfig;
var
  j: TJSONCodec;
  got: TDateTime;
begin
  // configured for RFC3339, handed a number
  j:= TJSONCodec.Create(ConfigWith(jdfRFC3339));
  try
    Assert.AreEqual(JSONOK,j.Unmarshal(IntToStr(EPOCH_SECONDS),got),'number under RFC3339');
    Assert.AreEqual(double(TheInstant),double(got),1/SecsPerDay);
  finally
    j.Free;
  end;

  // configured for epoch, handed a string
  j:= TJSONCodec.Create(ConfigWith(jdfEpoch));
  try
    Assert.AreEqual(JSONOK,j.Unmarshal(RFC3339_TEXT,got),'string under epoch');
    Assert.AreEqual(double(TheInstant),double(got),1/MSecsPerDay);
  finally
    j.Free;
  end;
end;

// the digits cannot say whether they are seconds or milliseconds, so this is
// the one thing decoding still takes from the config
procedure TConfigTest.TestNumberUnitComesFromTheConfig;
var
  j: TJSONCodec;
  asSeconds,asMillis,misread: TDateTime;
begin
  j:= TJSONCodec.Create(ConfigWith(jdfEpoch));
  try
    Assert.AreEqual(JSONOK,j.Unmarshal(IntToStr(EPOCH_SECONDS),asSeconds));
  finally
    j.Free;
  end;

  j:= TJSONCodec.Create(ConfigWith(jdfEpochMillis));
  try
    Assert.AreEqual(JSONOK,j.Unmarshal(IntToStr(EPOCH_MILLIS),asMillis));
    // seconds read as milliseconds land three weeks after the epoch: the setting
    // matters
    Assert.AreEqual(JSONOK,j.Unmarshal(IntToStr(EPOCH_SECONDS),misread));
    Assert.IsTrue(misread < EncodeDate(1971,1,1),'seconds misread as millis');
  finally
    j.Free;
  end;

  // both spellings name the same instant, to the resolution the coarser one
  // can carry - EPOCH_SECONDS has no room for the .123
  Assert.AreEqual(double(asSeconds),double(asMillis),1/SecsPerDay);
end;

// a date inside a variant goes through a different formatter, and must not
// disagree with the one for a plain TDateTime
procedure TConfigTest.TestVariantDateUsesTheSameFormat;
var
  j: TJSONCodec;
  v: Variant;
  s: string;
begin
  v:= VarAsType(TheInstant,varDate);

  j:= TJSONCodec.Create(ConfigWith(jdfEpoch));
  try
    Assert.AreEqual(JSONOK,j.Marshal(v,s));
    Assert.AreEqual(IntToStr(EPOCH_SECONDS),s);
  finally
    j.Free;
  end;

  j:= TJSONCodec.Create(ConfigWith(jdfRFC3339));
  try
    Assert.AreEqual(JSONOK,j.Marshal(v,s));
    Assert.AreEqual(RFC3339_TEXT,s);
  finally
    j.Free;
  end;
end;

procedure TConfigTest.TestDateTimeRejectsALiteral;
var
  got: TDateTime;
begin
  Assert.AreNotEqual(JSONOK,JSON.Unmarshal('null',got),'null');
  Assert.AreNotEqual(JSONOK,JSON.Unmarshal('true',got),'true');
end;

initialization
  TDUnitX.RegisterTestFixture(TConfigTest);

end.
