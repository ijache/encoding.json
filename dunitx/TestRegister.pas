unit TestRegister;

// RegisterParser/RegisterFormatter. The handlers use only the public reader and
// writer - if that is not enough, the feature is decorative. Every test builds its
// own TJSONCodec: a registration on the global JSON would leak into other fixtures.

interface

uses
  DUnitX.TestFramework;

type
  TMoney = record
    Cents: int64;
  end;
  PMoney = ^TMoney;

  TWallet = record
    Owner: string;
    Balance: TMoney;
  end;

  TAnimal = class
  public
    Name: string;
  end;

  TDog = class(TAnimal)
  public
    Toy: string;
  end;

  TNullableInt = record
    HasValue: boolean;
    Value: integer;
  end;
  PNullableInt = ^TNullableInt;

  TReading = record
    Sensor: string;
    Value: TNullableInt;
  end;

  // JSON text a handler writes as it is, unquoted
  TRawJSON = record
    Text: string;
  end;
  PRawJSON = ^TRawJSON;

  [TestFixture]
  TRegisterTest = class
  public
    [Test] procedure TestFormatterByQualifiedName;
    [Test] procedure TestParserByQualifiedName;
    [Test] procedure TestRegisterByTypeInfo;
    [Test] procedure TestRegisterByGenericParameter;
    [Test] procedure TestRegistrationAfterTheCacheIsWarm;
    [Test] procedure TestParserRegistrationAfterTheCacheIsWarm;
    [Test] procedure TestRegistrationAfterAnArrayIsWarm;
    [Test] procedure TestReplacesABuiltInRatherThanShadowingIt;
    [Test] procedure TestNilRemovesAHandler;
    [Test] procedure TestNameMatchesTheWholeAncestry;
    [Test] procedure TestRegistrationIsPerInstance;
    [Test] procedure TestRepeatedRegistrationDoesNotAccumulate;
    [Test] procedure TestDelegatingToABuiltIn;
    [Test] procedure TestUnquotedTextGoesOutAsItIs;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  encoding.json;

const
  MONEY_TYPE = 'TestRegister.TMoney';

type
  // down here on purpose: no qualified name, so only <T> or PTypeInfo can reach it.
  // "type TMoney" keeps TMoney's layout, with type info of its own
  TLocalMoney = type TMoney;

  TLocalWallet = record
    Owner: string;
    Balance: TLocalMoney;
  end;

// 150 cents as "1.50". negative amounts would need more care than this - it is
// a test fixture, not a currency library.
function FormatMoney(j: TJSONCodec; w: PJSONWriter; ti: PTypeInfo; data: Pointer): TJSONResult;
begin
  w.WriteString(Format('%d.%.2d',[PMoney(data).Cents div 100,PMoney(data).Cents mod 100]));
  result:= JSONOK;
end;

function ParseMoney(j: TJSONCodec; r: PJSONReader; ti: PTypeInfo; data: Pointer): TJSONResult;
var
  s: string;
  p: integer;
  vt: TJSONValueType;
begin
  result:= r.ReadValue(@vt);
  if result <> JSONOK then exit;
  if vt <> jvtString then exit(JSONTypeMismatch);

  s:= r.LastValue;
  p:= Pos('.',s);
  if p = 0 then exit(JSONSyntax);

  PMoney(data).Cents:= StrToInt64Def(Copy(s,1,p-1),0)*100 + StrToInt64Def(Copy(s,p+1,2),0);
end;

function FormatDateAsWord(j: TJSONCodec; w: PJSONWriter; ti: PTypeInfo; data: Pointer): TJSONResult;
begin
  w.WriteString('a date');
  result:= JSONOK;
end;

function FormatAnimal(j: TJSONCodec; w: PJSONWriter; ti: PTypeInfo; data: Pointer): TJSONResult;
begin
  w.WriteString('an animal');
  result:= JSONOK;
end;

function AWallet: TWallet;
begin
  result.Owner:= 'John';
  result.Balance.Cents:= 150;
end;

{ TRegisterTest }

procedure TRegisterTest.TestFormatterByQualifiedName;
var
  j: TJSONCodec;
  s: string;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    j.RegisterFormatter(MONEY_TYPE,@FormatMoney);
    Assert.AreEqual(JSONOK,j.Marshal(AWallet,s));
    Assert.AreEqual('{"Owner":"John","Balance":"1.50"}',s);
  finally
    j.Free;
  end;
end;

procedure TRegisterTest.TestParserByQualifiedName;
var
  j: TJSONCodec;
  got: TWallet;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    j.RegisterParser(MONEY_TYPE,@ParseMoney);
    Assert.AreEqual(JSONOK,j.Unmarshal('{"Owner":"John","Balance":"1.50"}',got));
    Assert.AreEqual('John',got.Owner);
    Assert.AreEqual(int64(150),got.Balance.Cents);
  finally
    j.Free;
  end;
end;

procedure TRegisterTest.TestRegisterByTypeInfo;
var
  j: TJSONCodec;
  s: string;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    j.RegisterFormatter(System.TypeInfo(TMoney),@FormatMoney);
    Assert.AreEqual(JSONOK,j.Marshal(AWallet,s));
    Assert.AreEqual('{"Owner":"John","Balance":"1.50"}',s);
  finally
    j.Free;
  end;
end;

procedure TRegisterTest.TestRegisterByGenericParameter;
var
  j: TJSONCodec;
  s: string;
  got: TWallet;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    j.RegisterFormatter<TMoney>(@FormatMoney);
    j.RegisterParser<TMoney>(@ParseMoney);

    Assert.AreEqual(JSONOK,j.Marshal(AWallet,s));
    Assert.AreEqual('{"Owner":"John","Balance":"1.50"}',s);

    Assert.AreEqual(JSONOK,j.Unmarshal(s,got));
    Assert.AreEqual(int64(150),got.Balance.Cents);
  finally
    j.Free;
  end;

  // the same for a type without a qualified name: keyed by its type info
  var localWallet, gotLocal: TLocalWallet;
  localWallet.Owner:= 'John';
  localWallet.Balance.Cents:= 150;

  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    j.RegisterFormatter<TLocalMoney>(@FormatMoney);
    j.RegisterParser<TLocalMoney>(@ParseMoney);

    Assert.AreEqual(JSONOK,j.Marshal(localWallet,s));
    Assert.AreEqual('{"Owner":"John","Balance":"1.50"}',s,'a non-public type');

    Assert.AreEqual(JSONOK,j.Unmarshal(s,gotLocal));
    Assert.AreEqual(int64(150),gotLocal.Balance.Cents,'a non-public type');
  finally
    j.Free;
  end;
end;

// TWallet's cache entry already holds Balance's formatter; registering
// must rebuild it, or the old {"Cents":150} comes out
procedure TRegisterTest.TestRegistrationAfterTheCacheIsWarm;
var
  j: TJSONCodec;
  s: string;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    Assert.AreEqual(JSONOK,j.Marshal(AWallet,s));
    Assert.AreEqual('{"Owner":"John","Balance":{"Cents":150}}',s,'before');

    j.RegisterFormatter(MONEY_TYPE,@FormatMoney);

    Assert.AreEqual(JSONOK,j.Marshal(AWallet,s));
    Assert.AreEqual('{"Owner":"John","Balance":"1.50"}',s,'after');
  finally
    j.Free;
  end;
end;

procedure TRegisterTest.TestParserRegistrationAfterTheCacheIsWarm;
var
  j: TJSONCodec;
  got: TWallet;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    Assert.AreEqual(JSONOK,j.Unmarshal('{"Owner":"John","Balance":{"Cents":150}}',got),'before');
    Assert.AreEqual(int64(150),got.Balance.Cents,'before');

    j.RegisterParser(MONEY_TYPE,@ParseMoney);

    got:= Default(TWallet);
    Assert.AreEqual(JSONOK,j.Unmarshal('{"Owner":"John","Balance":"2.25"}',got),'after');
    Assert.AreEqual(int64(225),got.Balance.Cents,'after');
  finally
    j.Free;
  end;
end;

// the handler of an array's element is cached too, once per TJSONCodec, so a
// registration has to reach it the way it reaches a struct member
procedure TRegisterTest.TestRegistrationAfterAnArrayIsWarm;
var
  j: TJSONCodec;
  s: string;
  wallets: TArray<TMoney>;
  got: TArray<TMoney>;
begin
  wallets:= [AWallet.Balance];
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    Assert.AreEqual(JSONOK,j.Marshal(wallets,s));
    Assert.AreEqual('[{"Cents":150}]',s,'before');
    Assert.AreEqual(JSONOK,j.Unmarshal('[{"Cents":150}]',got),'before');

    j.RegisterFormatter(MONEY_TYPE,@FormatMoney);
    j.RegisterParser(MONEY_TYPE,@ParseMoney);

    Assert.AreEqual(JSONOK,j.Marshal(wallets,s));
    Assert.AreEqual('["1.50"]',s,'after');
    Assert.AreEqual(JSONOK,j.Unmarshal('["2.25"]',got),'after');
    Assert.AreEqual(int64(225),got[0].Cents,'after');
  finally
    j.Free;
  end;
end;

// a known name is overwritten, not appended - the lookup takes the first match.
// Lower case on purpose: replace and lookup compare alike
procedure TRegisterTest.TestReplacesABuiltInRatherThanShadowingIt;
var
  j: TJSONCodec;
  s: string;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    j.RegisterFormatter('system.tdatetime',@FormatDateAsWord);
    Assert.AreEqual(JSONOK,j.Marshal(Now,s));
    Assert.AreEqual('"a date"',s);
  finally
    j.Free;
  end;
end;

// nil removes the entry: a TDateTime falls back to a bare float
procedure TRegisterTest.TestNilRemovesAHandler;
var
  j: TJSONCodec;
  s: string;
  d: double;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    j.RegisterFormatter('System.TDateTime',nil);
    Assert.AreEqual(JSONOK,j.Marshal(Now,s));
    Assert.IsFalse(s.StartsWith('"'),'should not be quoted any more: '+s);
    Assert.IsTrue(TryStrToFloat(s,d,TFormatSettings.Invariant),'should be a number: '+s);
  finally
    j.Free;
  end;
end;

// a class is matched against its whole ancestry, so a handler registered for
// the base type serves the descendants
procedure TRegisterTest.TestNameMatchesTheWholeAncestry;
var
  j: TJSONCodec;
  dog: TDog;
  s: string;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  dog:= TDog.Create;
  try
    dog.Name:= 'Rex';
    dog.Toy:= 'ball';

    Assert.AreEqual(JSONOK,j.Marshal(dog,s));
    // a class lists its own fields before the inherited ones
    Assert.AreEqual('{"Toy":"ball","Name":"Rex"}',s,'before');

    j.RegisterFormatter('TestRegister.TAnimal',@FormatAnimal);

    Assert.AreEqual(JSONOK,j.Marshal(dog,s));
    Assert.AreEqual('"an animal"',s,'after');
  finally
    dog.Free;
    j.Free;
  end;
end;

procedure TRegisterTest.TestRegistrationIsPerInstance;
var
  j: TJSONCodec;
  s: string;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    j.RegisterFormatter(MONEY_TYPE,@FormatMoney);
    Assert.AreEqual(JSONOK,j.Marshal(AWallet,s));
    Assert.AreEqual('{"Owner":"John","Balance":"1.50"}',s,'own instance');

    Assert.AreEqual(JSONOK,JSON.Marshal(AWallet,s));
    Assert.AreEqual('{"Owner":"John","Balance":{"Cents":150}}',s,'global instance');
  finally
    j.Free;
  end;
end;

function LiveBlocks: NativeInt;
var
  ms: TMemoryManagerState;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  GetMemoryManagerState(ms);
  {$WARN SYMBOL_PLATFORM ON}
  result:= ms.AllocatedLargeBlockCount + ms.AllocatedMediumBlockCount;
  for var i:= 0 to High(ms.SmallBlockTypeStates) do
    inc(result,ms.SmallBlockTypeStates[i].AllocatedBlockCount);
end;

// each registration frees the old cache instead of retiring it. Measured against
// a loop that only marshals, which holds one block as well
procedure TRegisterTest.TestRepeatedRegistrationDoesNotAccumulate;
const
  ROUNDS = 50;
var
  j: TJSONCodec;
  s: string;
  mark: NativeInt;
  marshalOnly,withRegistration: NativeInt;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    // warm up: the first use of these types fills the global RTTI pool and
    // sizes the result string, and none of that comes back
    j.RegisterFormatter(MONEY_TYPE,@FormatMoney);
    Assert.AreEqual(JSONOK,j.Marshal(AWallet,s));

    mark:= LiveBlocks;
    for var i:= 1 to ROUNDS do j.Marshal(AWallet,s);
    marshalOnly:= LiveBlocks - mark;

    mark:= LiveBlocks;
    for var i:= 1 to ROUNDS do begin
      j.RegisterFormatter(MONEY_TYPE,@FormatMoney);
      j.Marshal(AWallet,s);
    end;
    withRegistration:= LiveBlocks - mark;

    Assert.AreEqual('{"Owner":"John","Balance":"1.50"}',s);
    Assert.IsTrue(withRegistration <= marshalOnly,
      Format('%d registrations held on to %d blocks against %d for the same '+
             'number of plain marshals - the old type cache is not '+
             'being freed',[ROUNDS,withRegistration,marshalOnly]));
  finally
    j.Free;
  end;
end;

// the delegation hook from docs/custom-handlers.md: null decided here, the number
// handed to the built-in, range check included
function FormatNullableInt(j: TJSONCodec; w: PJSONWriter; ti: PTypeInfo; data: Pointer): TJSONResult;
var
  f: TJSONFormatter;
begin
  if not PNullableInt(data).HasValue then begin
    w.WriteNull;
    exit(JSONOK);
  end;
  f:= j.GetFormatterForTypeInfo(TypeInfo(integer));
  result:= f(j,w,TypeInfo(integer),@PNullableInt(data).Value);
end;

function ParseNullableInt(j: TJSONCodec; r: PJSONReader; ti: PTypeInfo; data: Pointer): TJSONResult;
var
  p: TJSONParser;
begin
  if r.PeekNextToken = 'n' then begin
    result:= r.ReadValue;
    if result = JSONOK then PNullableInt(data).HasValue:= false;
    exit;
  end;
  p:= j.GetParserForTypeInfo(TypeInfo(integer));
  result:= p(j,r,TypeInfo(integer),@PNullableInt(data).Value);
  PNullableInt(data).HasValue:= (result = JSONOK);
end;

procedure TRegisterTest.TestDelegatingToABuiltIn;
var
  j: TJSONCodec;
  s: string;
  reading,got: TReading;
  p: TJSONParser;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    j.RegisterFormatter<TNullableInt>(@FormatNullableInt);
    j.RegisterParser<TNullableInt>(@ParseNullableInt);

    reading.Sensor:= 'a';
    reading.Value.HasValue:= true;
    reading.Value.Value:= 42;
    Assert.AreEqual(JSONOK,j.Marshal(reading,s));
    Assert.AreEqual('{"Sensor":"a","Value":42}',s);

    got:= Default(TReading);
    Assert.AreEqual(JSONOK,j.Unmarshal(s,got));
    Assert.IsTrue(got.Value.HasValue);
    Assert.AreEqual(42,got.Value.Value);

    reading.Value.HasValue:= false;
    Assert.AreEqual(JSONOK,j.Marshal(reading,s));
    Assert.AreEqual('{"Sensor":"a","Value":null}',s);

    got.Value.HasValue:= true;
    Assert.AreEqual(JSONOK,j.Unmarshal(s,got));
    Assert.IsFalse(got.Value.HasValue,'null is the handler''s own decision');

    // and what an integer refuses comes back refused, by the built-in
    Assert.AreEqual(JSONTypeMismatch,j.Unmarshal('{"Sensor":"a","Value":"x"}',got),'a string');
    Assert.AreEqual(JSONTypeMismatch,j.Unmarshal('{"Sensor":"a","Value":3000000000}',got),'out of range');

    // the hook answers with the registry, so asking for the handler's own
    // type returns the handler itself: the built-in it replaced is gone
    p:= j.GetParserForTypeInfo(TypeInfo(TNullableInt));
    Assert.IsTrue(@p = @ParseNullableInt,'no way back to a replaced built-in');
  finally
    j.Free;
  end;
end;

function FormatRawJSON(j: TJSONCodec; w: PJSONWriter; ti: PTypeInfo; data: Pointer): TJSONResult;
begin
  w.WriteRaw(PRawJSON(data).Text);
  result:= JSONOK;
end;

// WriteRaw text goes out as UTF-8 with nothing escaped, a surrogate pair as its
// one character
procedure TRegisterTest.TestUnquotedTextGoesOutAsItIs;
var
  j: TJSONCodec;
  raw: TRawJSON;
  s: string;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    j.RegisterFormatter<TRawJSON>(@FormatRawJSON);

    // {"Gruesse":<tab>"a\"b\\c <smiley>"}, with u-umlaut and sharp s - from
    // parts, so this file stays ASCII
    raw.Text:= '{"Gr' + #$00FC#$00DF + 'e":' + #9 + '"a\"b\\c ' + #$D83D#$DE00 + '"}';
    Assert.AreEqual(JSONOK,j.Marshal(raw,s));
    Assert.AreEqual(raw.Text,s,'as it is');

    // a lone surrogate has no UTF-8 form: U+FFFD, as in a quoted string
    raw.Text:= '"x' + #$D800 + '"';
    Assert.AreEqual(JSONOK,j.Marshal(raw,s));
    Assert.AreEqual('"x' + #$FFFD + '"',s,'a lone surrogate');
  finally
    j.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRegisterTest);

end.
