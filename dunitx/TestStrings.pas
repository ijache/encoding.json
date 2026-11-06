unit TestStrings;

interface

uses
  DUnitX.TestFramework,
  System.Classes,
  encoding.json;

type
  [TestFixture]
  TStringsTest = class
  public
    [Test] procedure TestEncode;
    [Test] procedure TestDecode;
    [Test] procedure TestKeyValueDetectionCanBeTurnedOff;
    [Test] procedure TestEmptyValueIsKept;
  end;

implementation

{ TStringsTest }

procedure TStringsTest.TestEncode;
var
  someStrings: TStringlist;
  wantJSON: string;
  wantResult: TJSONResult;
  gotJSON: string;
  gotResult: TJSONResult;
begin

  someStrings:= TStringlist.Create();

  // test empty list
  wantJSON:= '[]';
  wantResult:= JSONOK;
  gotResult:= JSON.Marshal(someStrings,gotJson);
  Assert.AreEqual(wantResult,gotResult);
  Assert.AreEqual(wantJSON,gotJSON);


  // test flat list
  someStrings.Add('Paul');
  someStrings.Add('Ringo');
  someStrings.Add('George');
  someStrings.Add('John');

  wantJSON:= '["Paul","Ringo","George","John"]';
  wantResult:= JSONOK;
  gotResult:= JSON.Marshal(someStrings,gotJson);
  Assert.AreEqual(wantResult,gotResult);
  Assert.AreEqual(wantJSON,gotJSON);


  // test name/value-pairs
  someStrings.Clear;
  someStrings.Add('Paul=McCartney');
  someStrings.Add('Ringo=Starr');
  someStrings.Add('George=Harrison');
  someStrings.Add('John=Lennon');

  wantJSON:= '{"Paul":"McCartney","Ringo":"Starr","George":"Harrison","John":"Lennon"}';
  wantResult:= JSONOK;
  gotResult:= JSON.Marshal(someStrings,gotJson);
  Assert.AreEqual(wantResult,gotResult);
  Assert.AreEqual(wantJSON,gotJSON);


  // one entry has no name, so it is an array - nothing may be dropped for want of a
  // key
  someStrings.Clear;
  someStrings.Add('Paul=McCartney');
  someStrings.Add('Ringo=Starr');
  someStrings.Add('--------------');
  someStrings.Add('George=Harrison');
  someStrings.Add('John=Lennon');

  wantJSON:= '["Paul=McCartney","Ringo=Starr","--------------","George=Harrison","John=Lennon"]';
  wantResult:= JSONOK;
  gotResult:= JSON.Marshal(someStrings,gotJson);
  Assert.AreEqual(wantResult,gotResult);
  Assert.AreEqual(wantJSON,gotJSON);


  // the same rule seen from the other end: a leading entry with no name is
  // enough to make the whole thing an array
  someStrings.Clear;
  someStrings.Add('The Beatles are:');
  someStrings.Add('Paul=McCartney');
  someStrings.Add('Ringo=Starr');
  someStrings.Add('George=Harrison');
  someStrings.Add('John=Lennon');

  wantJSON:= '["The Beatles are:","Paul=McCartney","Ringo=Starr","George=Harrison","John=Lennon"]';
  wantResult:= JSONOK;
  gotResult:= JSON.Marshal(someStrings,gotJson);
  Assert.AreEqual(wantResult,gotResult);
  Assert.AreEqual(wantJSON,gotJSON);

  someStrings.Free;
end;


procedure TStringsTest.TestDecode;
var
  someJSON: string;
  gotStrings: TStringlist;
  gotResult: TJSONResult;
  wantStrings: TStringlist;
  wantResult: TJSONResult;
begin

  gotStrings:= TStringlist.Create;
  wantStrings:= TStringlist.Create;

  // test empty list
  someJSON:= '[]';
  wantResult:= JSONOK;

  gotResult:= JSON.Unmarshal(someJSON,gotStrings);
  Assert.AreEqual(wantResult,gotResult);
  Assert.AreEqual(wantStrings,gotStrings);


  // test flat list
  someJSON:= '["Paul","Ringo","George","John"]';
  wantStrings.Clear;
  wantStrings.Add('Paul');
  wantStrings.Add('Ringo');
  wantStrings.Add('George');
  wantStrings.Add('John');
  wantResult:= JSONOK;

  gotResult:= JSON.Unmarshal(someJSON,gotStrings);
  Assert.AreEqual(wantResult,gotResult);
  Assert.AreEqual(wantStrings,gotStrings);

  // test name/value-pairs
  wantStrings.Clear;
  wantStrings.Add('Paul=McCartney');
  wantStrings.Add('Ringo=Starr');
  wantStrings.Add('George=Harrison');
  wantStrings.Add('John=Lennon');
  wantResult:= JSONOK;

  someJSON:= '{"Paul":"McCartney","Ringo":"Starr","George":"Harrison","John":"Lennon"}';
  gotResult:= JSON.Unmarshal(someJSON,gotStrings);
  Assert.AreEqual(wantResult,gotResult);
  Assert.AreEqual(wantStrings,gotStrings);

  gotStrings.Free;
  wantStrings.Free;
end;


// with DetectKeyValuePairs off it is always an array
procedure TStringsTest.TestKeyValueDetectionCanBeTurnedOff;
var
  someStrings: TStringlist;
  plainJSON: TJSONCodec;
  config: TJSONConfig;
  gotJSON: string;
begin
  someStrings:= TStringlist.Create;
  config:= JSONDefaultConfig;
  config.DetectKeyValuePairs:= false;
  plainJSON:= TJSONCodec.Create(config);
  try
    someStrings.Add('Paul=McCartney');
    someStrings.Add('Ringo=Starr');

    // the default instance still detects
    Assert.AreEqual(JSONOK,JSON.Marshal(someStrings,gotJSON));
    Assert.AreEqual('{"Paul":"McCartney","Ringo":"Starr"}',gotJSON,'detection on');

    Assert.AreEqual(JSONOK,plainJSON.Marshal(someStrings,gotJSON));
    Assert.AreEqual('["Paul=McCartney","Ringo=Starr"]',gotJSON,'detection off');
  finally
    plainJSON.Free;
    someStrings.Free;
  end;
end;


// "a=" has a name and stays {"a":""} - Values[] := '' would delete it
procedure TStringsTest.TestEmptyValueIsKept;
var
  gotStrings: TStringlist;
  gotJSON: string;
begin
  gotStrings:= TStringlist.Create;
  try
    Assert.AreEqual(JSONOK,JSON.Unmarshal('{"a":"","b":"2"}',gotStrings));
    Assert.AreEqual(2,gotStrings.Count,'the empty member is still there');
    Assert.AreEqual('a=',gotStrings[0]);
    Assert.AreEqual(JSONOK,JSON.Marshal(gotStrings,gotJSON));
    Assert.AreEqual('{"a":"","b":"2"}',gotJSON,'and it round-trips');

    Assert.AreEqual(JSONOK,JSON.Unmarshal('{"a":"1","b":"2","a":""}',gotStrings));
    Assert.AreEqual(2,gotStrings.Count,'a repeated key replaces, it does not add');
    Assert.AreEqual('a=',gotStrings[0],'...and the last one wins, even when empty');
  finally
    gotStrings.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TStringsTest);

end.
