unit TestGotchas;

// One test per entry in the Gotchas of docs/limits-and-gotchas.md. Each is a
// decision, not a discovery: change one and its test fails - then edit the docs too.

interface

uses
  DUnitX.TestFramework,
  SysUtils,
  Classes,
  Generics.Collections,
  System.UITypes,
  encoding.json;

type
  TInner = class
  public
    Alpha: integer;
  end;

  // tells "freed" apart from "dropped": the suite's leak count is DUnitX's
  // default monitor, which measures nothing, so a dropped instance would pass
  TCountedInner = class(TInner)
  public
    class var Destroyed: integer;
    destructor Destroy; override;
  end;

  THolder = record
    Name: string;
    Inner: TInner;
  end;

  TTwo = record
    A: integer;
    B: integer;
  end;

  TFourInts = array[0..3] of integer;

  TFourHolder = record
    Items: TFourInts;
  end;

  TEnum = (eA,eB);
  TEnumSet = set of TEnum;

  TFloatHolder = record
    V: double;
  end;

  TVariantHolder = record
    V: Variant;
  end;

  TPercent = 0..100;

  TRanges = record
    AShortInt: ShortInt;
    AByte: Byte;
    AWord: Word;
    AInteger: Integer;
    Percent: TPercent;
  end;

  TProcOfObject = procedure of object;
  TPlainProc = procedure;

  TWithUnmappable = record
    Name: string;
    Service: IInterface;
    Callback: TProcOfObject;
    Plain: TPlainProc;
    Later: TProc;
    Kind: TClass;
    Data: Pointer;
  end;

  TWithUnmappableInside = record
    Name: string;
    Services: TArray<IInterface>;
  end;

  TPointerHolder = record
    P: PInteger;
  end;

  TAnimal = class
  public
    Name: string;
  end;

  TDog = class(TAnimal)
  public
    Barks: boolean;
  end;

  TPetHolder = record
    Pet: TAnimal;
  end;

  // only a constructor with a parameter, which decoding cannot call
  TWithOwnConstructor = class
  public
    Name: string;
    Tags: TStringList;
    constructor Create(const aName: string);
    destructor Destroy; override;
  end;

  TCaseKeys = record
    FirstName: string;
    [JSON('K'#$00F6'ln')] City: integer;
  end;

  TTwoSpellings = record
    [JSON('a')] Lower: integer;
    [JSON('A')] Upper: integer;
  end;

  [TestFixture]
  TGotchasTest = class
  public
    [Test] procedure TestEmptyObjectBuildsTheInstance;
    [Test] procedure TestNullIsNotAnEmptyValue;
    [Test] procedure TestLastDuplicateKeyWins;
    [Test] procedure TestObjectsMergeIntoTheDestination;
    [Test] procedure TestAggregatesReplaceTheDestination;
    [Test] procedure TestStaticArrayNeedsAnExactMatch;
    [Test] procedure TestDateTimeIsUTCByDefault;
    [Test] procedure TestStringsCannotHoldEveryKey;
    [Test] procedure TestStringsTakeAnyScalarAsText;
    [Test] procedure TestNonFiniteFloatsCannotBeEncoded;
    [Test] procedure TestLongFloatsMayComeBackAsANeighbour;
    [Test] procedure TestNullIntoAClassFreesTheInstance;
    [Test] procedure TestNullIntoAPointerFreesNothing;
    [Test] procedure TestMemberWithoutAHandlerIsSkipped;
    [Test] procedure TestOutOfRangeIsRefusedNotTruncated;
    [Test] procedure TestRealIntoAnIntegerIsRefused;
    [Test] procedure TestSystemColourCannotBeWritten;
    [Test] procedure TestLoneSurrogateBecomesAReplacementCharacter;
    [Test] procedure TestInterfacedObjectEncodesRefCount;
    [Test] procedure TestStringsAreAnObjectOnlyIfEveryEntryHasAName;
    [Test] procedure TestEncodingGoesByTheDeclaredType;
    [Test] procedure TestOnlyAParameterlessConstructorRuns;
    [Test] procedure TestKeysMatchMembersIgnoringASCIICase;
  end;

  TCountedDto = class(TInterfacedObject)
  public
    Name: string;
  end;

  TQuietDto = class(TInterfacedObject)
  public
    Name: string;
    [JSON('-')] property RefCount;
  end;

implementation

uses
  Variants,
  Math,
  DateUtils;

destructor TCountedInner.Destroy;
begin
  inc(Destroyed);
  inherited;
end;

{ TGotchasTest }

// "{}" is an empty value, not an absent one: it builds the instance, the same
// way "[]" has always built a TList. "null" is how a document says nothing.
procedure TGotchasTest.TestEmptyObjectBuildsTheInstance;
var
  holder: THolder;
  gotResult: TJSONResult;
begin
  holder:= Default(THolder);

  gotResult:= JSON.Unmarshal(UTF8String('{"Name":"n","Inner":{}}'),holder);
  try
    Assert.AreEqual(JSONOK,gotResult);
    Assert.IsTrue(holder.Inner <> nil,'an empty object still builds its instance');
    Assert.AreEqual(0,holder.Inner.Alpha,'...with its fields left at their defaults');
  finally
    holder.Inner.Free;
  end;
end;

// "the document said nothing" is not "the value is zero"; only a class, a
// Variant and a set have a way to say nothing
procedure TGotchasTest.TestNullIsNotAnEmptyValue;
var
  someInt: integer;
  someString: string;
  someDate: TDateTime;
  someObject: TInner;
  someSet: TEnumSet;
  someVariant: Variant;
begin
  someInt:= 7;
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('null'),someInt),'null into an integer');

  someString:= 'x';
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('null'),someString),'null into a string');

  someDate:= 1;
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('null'),someDate),'null into a TDateTime');

  // a class takes it - see TestNullIntoAClassFreesTheInstance
  someObject:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('null'),someObject),'null into a class');
  Assert.IsTrue(someObject = nil,'...is nil');

  someSet:= [eB];
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('null'),someSet),'null into a set');
  Assert.IsTrue(someSet = [],'...is the empty set');

  someVariant:= 1;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('null'),someVariant),'null into a Variant');
  Assert.IsTrue(VarIsNull(someVariant),'...is varNull');
end;

// JSON does not forbid a repeated key and does not say what it means. We take
// the last one, which is what most parsers do.
procedure TGotchasTest.TestLastDuplicateKeyWins;
var
  two: TTwo;
  gotResult: TJSONResult;
begin
  two:= Default(TTwo);

  gotResult:= JSON.Unmarshal(UTF8String('{"A":1,"A":2,"A":3}'),two);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(3,two.A,'the last occurrence wins');
end;

// a member the document does not name keeps what it held
procedure TGotchasTest.TestObjectsMergeIntoTheDestination;
var
  two: TTwo;
  gotResult: TJSONResult;
begin
  two.A:= 91;
  two.B:= 92;

  gotResult:= JSON.Unmarshal(UTF8String('{"A":1}'),two);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(1,two.A,'the member the document names is written');
  Assert.AreEqual(92,two.B,'the one it does not name is left alone');
end;

// An aggregate is a whole value rather than a set of named parts, so it
// replaces what the destination held. Containers are cleared first.
procedure TGotchasTest.TestAggregatesReplaceTheDestination;
var
  someList: TList<integer>;
  someStrings: TStringList;
  someDict: TDictionary<string,integer>;
  someArray,sharedArray: TArray<integer>;
  someSet: TEnumSet;
begin
  someArray:= [90,91,92,93];
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('[1,2]'),someArray));
  Assert.AreEqual(2,integer(Length(someArray)),'a dynamic array is resized, not merged into');

  // replaced as an assignment would: a variable sharing the old array keeps it
  someArray:= [90,91,92];
  sharedArray:= someArray;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('[1,2,3]'),someArray));
  Assert.AreEqual(1,someArray[0]);
  Assert.AreEqual(90,sharedArray[0],'the same length leaves the sharer alone');
  Assert.AreEqual(92,sharedArray[2]);

  someArray:= [90,91,92];
  sharedArray:= someArray;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('[1]'),someArray));
  Assert.AreEqual(90,sharedArray[0],'so does a shorter document');
  Assert.AreEqual(3,integer(Length(sharedArray)));

  someSet:= [eA];
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('["eB"]'),someSet));
  Assert.IsTrue(someSet = [eB],'a set is replaced, not added to');

  someList:= TList<integer>.Create;
  try
    someList.AddRange([90,91,92,93]);
    Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('[1,2]'),someList));
    Assert.AreEqual(2,integer(someList.Count),'a TList is cleared first');
  finally
    someList.Free;
  end;

  someStrings:= TStringList.Create;
  try
    someStrings.Add('old');
    Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('["a"]'),someStrings));
    Assert.AreEqual(1,someStrings.Count,'a TStrings is cleared first');
  finally
    someStrings.Free;
  end;

  someDict:= TDictionary<string,integer>.Create;
  try
    someDict.Add('old',9);
    Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"a":1}'),someDict));
    Assert.AreEqual(1,integer(someDict.Count),'a TDictionary is cleared first');
    Assert.IsFalse(someDict.ContainsKey('old'),'...so the old key is gone');
  finally
    someDict.Free;
  end;
end;

// a static array's length is part of its type - a short document would leave
// stale slots or invent zeros
procedure TGotchasTest.TestStaticArrayNeedsAnExactMatch;
var
  holder: TFourHolder;
begin
  holder.Items[0]:= 90;
  holder.Items[1]:= 91;
  holder.Items[2]:= 92;
  holder.Items[3]:= 93;

  Assert.AreEqual(JSONTypeMismatch,
    JSON.Unmarshal(UTF8String('{"Items":[1,2]}'),holder),'too few elements');
  Assert.AreEqual(JSONTypeMismatch,
    JSON.Unmarshal(UTF8String('{"Items":[1,2,3,4,5]}'),holder),'too many elements');
  Assert.AreEqual(JSONTypeMismatch,
    JSON.Unmarshal(UTF8String('{"Items":[]}'),holder),'no elements at all');

  Assert.AreEqual(JSONOK,
    JSON.Unmarshal(UTF8String('{"Items":[1,2,3,4]}'),holder),'exactly four');
  Assert.AreEqual(4,holder.Items[3]);
end;

// a local Now goes out as if it were UTC; DateTimeIsUTC off converts both ways
procedure TGotchasTest.TestDateTimeIsUTCByDefault;
var
  wallClock: TDateTime;
  gotJSON: string;
  c: TJSONConfig;
  j: TJSONCodec;
begin
  wallClock:= EncodeDateTime(2024,6,9,12,30,45,0);

  Assert.AreEqual(JSONOK,JSON.Marshal(wallClock,gotJSON));
  Assert.AreEqual('"2024-06-09T12:30:45.000Z"',gotJSON,false,'taken as UTC, not converted');

  c:= JSONDefaultConfig;
  c.DateTimeIsUTC:= false;
  j:= TJSONCodec.Create(c);
  try
    Assert.AreEqual(JSONOK,j.Marshal(TTimeZone.Local.ToLocalTime(wallClock),gotJSON));
    Assert.AreEqual('"2024-06-09T12:30:45.000Z"',gotJSON,false,'local time, converted to UTC');
  finally
    j.Free;
  end;
end;

// a key containing the separator, or an empty one, is taken and reads back as
// something else - the loose destination does not refuse
procedure TGotchasTest.TestStringsCannotHoldEveryKey;
var
  someStrings: TStringList;
  gotJSON: string;
begin
  someStrings:= TStringList.Create;
  try
    Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"a=b":"1"}'),someStrings));
    Assert.AreEqual('a=b=1',someStrings[0],'the key goes in as given');
    Assert.AreEqual(JSONOK,JSON.Marshal(someStrings,gotJSON));
    Assert.AreEqual('{"a":"b=1"}',gotJSON,'...and splits at the first "=" coming out');

    Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"":"1"}'),someStrings));
    Assert.AreEqual('=1',someStrings[0],'an empty key goes in as given');
    Assert.AreEqual(JSONOK,JSON.Marshal(someStrings,gotJSON));
    Assert.AreEqual('["=1"]',gotJSON,'...and has no name coming out, so it is an array');
  finally
    someStrings.Free;
  end;
end;

// any scalar goes in as its text; null as '', not as the text "null"
procedure TGotchasTest.TestStringsTakeAnyScalarAsText;
var
  someStrings: TStringList;
  gotJSON: string;
begin
  someStrings:= TStringList.Create;
  try
    Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('["a",1,true,null]'),someStrings));
    Assert.AreEqual(JSONOK,JSON.Marshal(someStrings,gotJSON));
    Assert.AreEqual('["a","1","true",""]',gotJSON,'the array form');

    Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"k":1,"b":false,"n":null}'),someStrings));
    Assert.AreEqual(JSONOK,JSON.Marshal(someStrings,gotJSON));
    Assert.AreEqual('{"k":"1","b":"false","n":""}',gotJSON,'the object form');

    Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('["a",[1]]'),someStrings),
      'an array as an element');
    Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('{"k":{}}'),someStrings),
      'an object as a value');
  finally
    someStrings.Free;
  end;
end;

// NaN and the infinities have no JSON form; refusing is the one choice that
// cannot lose data silently
procedure TGotchasTest.TestNonFiniteFloatsCannotBeEncoded;
var
  someFloat: TFloatHolder;
  someVariant: TVariantHolder;
  gotJSON: string;
  gotInfo: TJSONErrorInfo;
begin
  someFloat.V:= NaN;
  Assert.AreEqual(JSONTypeMismatch,JSON.Marshal(someFloat,gotJSON,@gotInfo),'a NaN member');
  Assert.AreEqual('V',gotInfo.MemberName,false,'and the member is named');

  someFloat.V:= Infinity;
  Assert.AreEqual(JSONTypeMismatch,JSON.Marshal(someFloat,gotJSON),'an infinity');

  someFloat.V:= NegInfinity;
  Assert.AreEqual(JSONTypeMismatch,JSON.Marshal(someFloat,gotJSON),'and a negative one');

  // the same value reached through a Variant takes the same route out
  someVariant.V:= NaN;
  Assert.AreEqual(JSONTypeMismatch,JSON.Marshal(someVariant,gotJSON),'a NaN inside a Variant');

  // a finite value next to it still encodes, so this is about the value and
  // not about the type
  someFloat.V:= 1.5;
  Assert.AreEqual(JSONOK,JSON.Marshal(someFloat,gotJSON));
  Assert.AreEqual('{"V":1.5}',gotJSON);
end;

// itself or the double next to it: a positive double's bits count up with it
function SameOrNeighbour(a,b: double): boolean;
begin
  result:= Abs(PInt64(@a)^ - PInt64(@b)^) <= 1;
end;

// written exactly, read exactly up to the fast path's limits; beyond them Win64's
// RTL may come back one bit off with JSONOK
procedure TGotchasTest.TestLongFloatsMayComeBackAsANeighbour;
var
  someFloat,gotFloat: TFloatHolder;
  gotJSON: string;
begin
  // 17 digits where the double needs them, read back by the RTL: on Win32
  // nearly always exactly, on Win64 possibly as the neighbour
  someFloat.V:= 1.2345678901234567;
  Assert.AreEqual(JSONOK,JSON.Marshal(someFloat,gotJSON));
  Assert.AreEqual('{"V":1.2345678901234567}',gotJSON,'the shortest exact digits');
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String(gotJSON),gotFloat));
  Assert.IsTrue(SameOrNeighbour(gotFloat.V,someFloat.V),'itself or a neighbour');

  // the ordinary case goes through the fast path and comes back bit for bit,
  // on every platform: a 16-digit coordinate, a short decimal
  someFloat.V:= -65.61361699999998;
  Assert.AreEqual(JSONOK,JSON.Marshal(someFloat,gotJSON));
  Assert.AreEqual('{"V":-65.61361699999998}',gotJSON);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String(gotJSON),gotFloat));
  Assert.IsTrue(gotFloat.V = someFloat.V,'16 digits, exactly');

  someFloat.V:= 3.14159;
  Assert.AreEqual(JSONOK,JSON.Marshal(someFloat,gotJSON));
  Assert.AreEqual('{"V":3.14159}',gotJSON);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String(gotJSON),gotFloat));
  Assert.IsTrue(gotFloat.V = someFloat.V,'a short decimal, exactly');

  // MaxDouble writes exactly and reads back without overflowing
  someFloat.V:= MaxDouble;
  Assert.AreEqual(JSONOK,JSON.Marshal(someFloat,gotJSON));
  Assert.AreEqual('{"V":1.7976931348623157E308}',gotJSON,'MaxDouble, exactly');
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String(gotJSON),gotFloat),'MaxDouble reads back');
  Assert.IsTrue(SameOrNeighbour(gotFloat.V,someFloat.V),'...as itself or a neighbour');

  someFloat.V:= -MaxDouble;
  Assert.AreEqual(JSONOK,JSON.Marshal(someFloat,gotJSON));
  Assert.AreEqual('{"V":-1.7976931348623157E308}',gotJSON,'and its negative likewise');
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String(gotJSON),gotFloat),'...reads back');
end;

// the target may come from AllocMem, New or the stack, so nothing is freed; in
// exchange a nil pointer round-trips
procedure TGotchasTest.TestNullIntoAPointerFreesNothing;
var
  someHolder,gotHolder: TPointerHolder;
  someInt: integer;
  gotJSON: string;
begin
  someHolder.P:= nil;
  Assert.AreEqual(JSONOK,JSON.Marshal(someHolder,gotJSON));
  Assert.AreEqual('{"P":null}',gotJSON,'nil goes out as null');

  gotHolder.P:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String(gotJSON),gotHolder),'null into a nil pointer');
  Assert.IsTrue(gotHolder.P = nil,'...comes back as nil');

  // the target is a stack local, so freeing it would not go unnoticed
  someInt:= 42;
  gotHolder.P:= @someInt;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"P":null}'),gotHolder),'null into a live pointer');
  Assert.IsTrue(gotHolder.P = nil,'...sets it to nil');
  Assert.AreEqual(42,someInt,'...and leaves what it pointed at alone');
end;

// RefCount is public, so it is encoded; redeclaring it with [JSON('-')] hides it
procedure TGotchasTest.TestInterfacedObjectEncodesRefCount;
var
  counted: TCountedDto;
  quiet: TQuietDto;
  s: string;
begin
  counted:= TCountedDto.Create;
  counted.Name:= 'x';
  Assert.AreEqual(JSONOK,JSON.Marshal(counted,s));
  Assert.AreEqual('{"Name":"x","RefCount":0}',s,false);
  counted.Free;

  quiet:= TQuietDto.Create;
  quiet.Name:= 'x';
  Assert.AreEqual(JSONOK,JSON.Marshal(quiet,s));
  Assert.AreEqual('{"Name":"x"}',s,false);
  quiet.Free;
end;

// the guess may be wrong, but never loses an entry - the middle case is the one
// first-and-last sampling could not see
procedure TGotchasTest.TestStringsAreAnObjectOnlyIfEveryEntryHasAName;
var
  someStrings: TStringlist;
  gotJSON: string;

  procedure AssertEncodes(const wantJSON,because: string);
  begin
    Assert.AreEqual(JSONOK,JSON.Marshal(someStrings,gotJSON),because);
    Assert.AreEqual(wantJSON,gotJSON,because);
  end;

begin
  someStrings:= TStringlist.Create;
  try
    someStrings.Add('one');
    someStrings.Add('two');
    AssertEncodes('["one","two"]','no names at all');

    someStrings.Clear;
    someStrings.Add('a=1');
    someStrings.Add('middle');
    someStrings.Add('c=3');
    AssertEncodes('["a=1","middle","c=3"]','a name missing in the middle');

    // an empty name is not a name
    someStrings.Clear;
    someStrings.Add('a=1');
    someStrings.Add('=2');
    AssertEncodes('["a=1","=2"]','an entry with an empty name');

    // every entry named - the object form, and still nothing lost
    someStrings.Clear;
    someStrings.Add('a=1');
    someStrings.Add('b=2');
    AssertEncodes('{"a":"1","b":"2"}','every entry named');
  finally
    someStrings.Free;
  end;
end;

// null is how a document says "no object here", and the destination owns what
// it points at - so the instance is freed, not merely dropped
procedure TGotchasTest.TestNullIntoAClassFreesTheInstance;
var
  someObject: TInner;
begin
  someObject:= TCountedInner.Create;
  TCountedInner.Destroyed:= 0;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('null'),someObject),'null into a class');
  Assert.IsTrue(someObject = nil,'...leaves nil');
  Assert.AreEqual(1,TCountedInner.Destroyed,'...and freed the instance rather than dropping it');
end;

// an interface, a method, a class reference, an untyped pointer: skipped both ways;
// anything that only contains one is refused
procedure TGotchasTest.TestMemberWithoutAHandlerIsSkipped;
var
  r: TWithUnmappable;
  inside: TWithUnmappableInside;
  s: string;
begin
  r:= Default(TWithUnmappable);
  r.Name:= 'x';
  r.Kind:= TObject;
  r.Data:= @r;
  Assert.AreEqual(JSONOK,JSON.Marshal(r,s));
  Assert.AreEqual('{"Name":"x"}',s);

  Assert.AreEqual(JSONOK,JSON.Unmarshal(
    '{"Name":"y","Service":{},"Callback":1,"Plain":2,"Later":3,"Kind":"TObject","Data":4}',r));
  Assert.AreEqual('y',r.Name);
  Assert.IsTrue(r.Service = nil,'nothing decoded into the interface');
  Assert.IsTrue(r.Data = @r,'nor into the pointer');

  inside:= Default(TWithUnmappableInside);
  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(inside,s),'an array of interfaces, even empty');
  Assert.AreEqual(JSONUnsupportedType,JSON.Unmarshal('{"Services":[]}',inside),'...both ways');
end;

// a number the destination cannot hold is refused, not cut down to fit - by
// the range the type itself declares, a subrange's included
procedure TGotchasTest.TestOutOfRangeIsRefusedNotTruncated;
var
  r: TRanges;
begin
  r:= Default(TRanges);
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal('{"AByte":300}',r),'300 into a byte');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal('{"AByte":-1}',r),'-1 into a byte');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal('{"AShortInt":200}',r),'200 into a shortint');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal('{"AWord":70000}',r),'70000 into a word');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal('{"AInteger":5000000000}',r),'5e9 into an integer');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal('{"Percent":101}',r),'101 into 0..100');
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal('{"Percent":-1}',r),'-1 into 0..100');

  // the boundaries themselves go in - the check is not off by one at either end
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"AByte":255,"AShortInt":-128,"Percent":100}',r));
  Assert.AreEqual(255,integer(r.AByte));
  Assert.AreEqual(-128,integer(r.AShortInt));
  Assert.AreEqual(100,integer(r.Percent));
end;

// the token's form decides, as in Go: 28.999999999999996 must not floor to 28
procedure TGotchasTest.TestRealIntoAnIntegerIsRefused;
var
  r: TRanges;

  procedure Refused(const someNumber: string);
  begin
    r.AInteger:= 7;
    Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal('{"AInteger":'+someNumber+'}',r),someNumber);
    Assert.AreEqual(7,r.AInteger,someNumber+' left the member alone');
  end;

begin
  Refused('1.9');
  Refused('-1.9');
  Refused('28.999999999999996');
  Refused('2.0');
  Refused('-0.0');
  Refused('1e2');
  Refused('1E2');
  Refused('1e30');

  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"AInteger":-29}',r));
  Assert.AreEqual(-29,r.AInteger,'a whole-number token still decodes');
end;

// a system colour is an index, not RGB - refused rather than written as another colour
procedure TGotchasTest.TestSystemColourCannotBeWritten;
var
  systemColour: TColor;
  s: string;
begin
  systemColour:= TColor($FF000005);
  Assert.AreEqual(JSONTypeMismatch,JSON.Marshal(systemColour,s));
end;

// a lone surrogate has no UTF-8 form: U+FFFD both ways, as in Go
procedure TGotchasTest.TestLoneSurrogateBecomesAReplacementCharacter;
var
  s: UTF8String;
  got: string;
begin
  Assert.AreEqual(JSONOK,JSON.Marshal(string('a'+#$D800+'b'),s));
  Assert.AreEqual(UTF8String('"a'+#$FFFD+'b"'),s,'a lone high surrogate');
  Assert.AreEqual(JSONOK,JSON.Marshal(string(#$DC00+#$D800),s));
  Assert.AreEqual(UTF8String('"'+#$FFFD+#$FFFD+'"'),s,'a pair in the wrong order is two');

  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('"a\ud800b"'),got));
  Assert.AreEqual(string('a'+#$FFFD+'b'),got,'an escaped one, decoded');
end;

// decoding can only build the declared type, so encoding writes it too
procedure TGotchasTest.TestEncodingGoesByTheDeclaredType;
var
  holder: TPetHolder;
  dog: TDog;
  asAnimal: TAnimal;
  s: string;
begin
  dog:= TDog.Create;
  dog.Name:= 'Rex';
  dog.Barks:= true;

  holder.Pet:= dog;
  Assert.AreEqual(JSONOK,JSON.Marshal(holder,s));
  Assert.AreEqual('{"Pet":{"Name":"Rex"}}',s,'a TDog in a TAnimal member');

  asAnimal:= dog;
  Assert.AreEqual(JSONOK,JSON.Marshal(asAnimal,s));
  Assert.AreEqual('{"Name":"Rex"}',s,'a TDog in a TAnimal variable');

  Assert.AreEqual(JSONOK,JSON.Marshal(dog,s));
  Assert.IsTrue(Pos('"Barks":true',s) > 0,'declared as a TDog, it is written as one');
  dog.Free;
end;

constructor TWithOwnConstructor.Create(const aName: string);
begin
  Name:= aName;
  Tags:= TStringList.Create;
end;

destructor TWithOwnConstructor.Destroy;
begin
  Tags.Free;
  inherited;
end;

// built through the nearest parameterless Create - here TObject's
procedure TGotchasTest.TestOnlyAParameterlessConstructorRuns;
var
  o: TWithOwnConstructor;
begin
  o:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"Name":"x"}',o));
  Assert.IsTrue(o <> nil,'an instance was built');
  Assert.AreEqual('x',o.Name);
  Assert.IsTrue(o.Tags = nil,'...without running its own constructor');
  o.Free;
end;

// a..z fold, other letters do not; of two members differing in case, the first
// declared wins even against an exact match
procedure TGotchasTest.TestKeysMatchMembersIgnoringASCIICase;
var
  r: TCaseKeys;
  two: TTwoSpellings;
begin
  r:= Default(TCaseKeys);
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"firstname":"a"}',r));
  Assert.AreEqual('a',r.FirstName,'all lower case');
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"FIRSTNAME":"b"}',r));
  Assert.AreEqual('b',r.FirstName,'all upper case');

  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"k'+#$00F6+'ln":1}',r));
  Assert.AreEqual(1,r.City,'the ASCII letters fold');
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"K'+#$00D6+'LN":2}',r));
  Assert.AreEqual(1,r.City,'...the others do not: another key, skipped');

  two:= Default(TTwoSpellings);
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"A":5}',two));
  Assert.AreEqual(5,two.Lower,'the first member declared takes the key');
  Assert.AreEqual(0,two.Upper,'...though the second matches it exactly');
end;

initialization
  TDUnitX.RegisterTestFixture(TGotchasTest);

end.
