unit TestSadPaths;

// Everything that must fail, and the exact code it fails with - the corpus only
// checks accept versus reject. Every case asserts one specific code, never just
// "not JSONOK". On top: no exception escapes, and a failed decode into a class
// leaves the variable nil.

interface

uses
  DUnitX.TestFramework,
  encoding.json;

type
  TColour = (clRed, clGreen, clBlue);
  TWarmColour = clRed..clGreen;

  TSadRecord = record
    Alpha: integer;
    Beta: string;
  end;
  PSadRecord = ^TSadRecord;

  TSadNested = record
    Name: string;
    Inner: TSadRecord;
  end;

  TSadObject = class
  public
    Alpha: integer;
  end;

  // counts its live instances, so a test can tell freed from orphaned
  TLiveCounted = class
  public
    Alpha: integer;
    class var Live: integer;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  end;

  TFourInts = array[0..3] of integer;

  // types without a handler. The method pointer is wrapped in an array: a bare
  // member of such a type is skipped, not refused (see the gotchas)
  TProc = procedure of object;
  TProcs = array of TProc;
  TPointers = array of Pointer;

  // explicit values: Delphi emits no type info for it, nor for a container's
  // element of that type
  TSparse = (spOne = 1, spFive = 5);
  PSparse = ^TSparse;
  // a named static array of it does have type info, with no element type in it
  TSparsePair = array[0..1] of TSparse;
  PInterface = ^IInterface;

  [TestFixture]
  TSadPathsTest = class
  private
    procedure Rejects<T>(want: TJSONResult; const src: UTF8String; const why: string);
    procedure Refuses<T>(want: TJSONResult; const v: T; const why: string);
  public
    // --- the document is broken -> JSONSyntax
    [Test] procedure TestEmptyAndTruncatedInput;
    [Test] procedure TestBytesThatCannotStartAValue;
    [Test] procedure TestMalformedNumbers;
    [Test] procedure TestMalformedStrings;
    [Test] procedure TestBrokenStructure;

    // --- the document is fine, the destination is wrong -> JSONTypeMismatch
    [Test] procedure TestScalarGivenAnAggregate;
    [Test] procedure TestScalarGivenTheWrongScalar;
    [Test] procedure TestAggregateGivenAScalar;
    [Test] procedure TestContainerGivenTheWrongAggregate;
    [Test] procedure TestValuesTheDestinationCannotHold;
    [Test] procedure TestValuesTheTypeCannotRepresent;
    [Test] procedure TestMismatchInsideAStruct;

    // --- the type cannot be mapped at all -> JSONUnsupportedType
    [Test] procedure TestUnmappableTypesOnDecode;
    [Test] procedure TestUnmappableTypesOnEncode;

    // --- contracts that the return value does not show
    [Test] procedure TestFailedDecodeLeavesTheDestinationNil;
    [Test] procedure TestFailureDoesNotFreeACallerSuppliedObject;
    [Test] procedure TestFailedArrayHoldsWhatWasDecoded;
    [Test] procedure TestFailedContainerFreesWhatItHeld;
    [Test] procedure TestHalfAccessiblePropertiesAreSkipped;
    [Test] procedure TestCyclicGraphStopsAtMaxDepth;
    [Test] procedure TestDictionaryWithANonStringKeyIsRejected;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Math,
  System.Generics.Collections;

// decodes into T and insists on exactly "want" - "<> JSONOK" would pass every
// mistake this fixture exists to catch
procedure TSadPathsTest.Rejects<T>(want: TJSONResult; const src: UTF8String; const why: string);
var
  got: TJSONResult;
  v: T;
  ti: PTypeInfo;
begin
  v:= Default(T);

  try
    got:= JSON.Unmarshal<T>(src,v);
  except
    on e: Exception do begin
      Assert.Fail(Format('%s: %s escaped the public API for <%s> - %s',
        [why,e.ClassName,string(src),e.Message]));
      exit;
    end;
  end;

  Assert.AreEqual(want,got,Format('%s, decoding <%s>',[why,string(src)]));

  // a failed decode into a class leaves nothing it constructed behind
  ti:= System.TypeInfo(T);
  if (ti <> nil) and (ti.Kind = tkClass) then
    Assert.IsTrue(PPointer(@v)^ = nil,
      Format('%s: destination must be left nil, decoding <%s>',[why,string(src)]));
end;

// the encode-side twin of Rejects
procedure TSadPathsTest.Refuses<T>(want: TJSONResult; const v: T; const why: string);
var
  got: TJSONResult;
  s: UTF8String;
begin
  try
    got:= JSON.Marshal<T>(v,s);
  except
    on e: Exception do begin
      Assert.Fail(Format('%s: %s escaped the public API - %s',[why,e.ClassName,e.Message]));
      exit;
    end;
  end;

  Assert.AreEqual(want,got,why);
end;


//----------------------------------------------------------------------------
// the document is broken
//----------------------------------------------------------------------------

// truncation is JSONSyntax too. The record cases cut an object one byte at a time:
// each position leaves the reader in a different state
procedure TSadPathsTest.TestEmptyAndTruncatedInput;
begin
  Rejects<TSadRecord>(JSONSyntax,'','empty input');
  Rejects<TSadRecord>(JSONSyntax,'   ','whitespace only');
  Rejects<integer>(JSONSyntax,'','empty input, scalar destination');

  // the bounds check comes after the whitespace is skipped
  Rejects<integer>(JSONSyntax,'   ','whitespace only, scalar destination');

  Rejects<TSadRecord>(JSONSyntax,'{','cut after the brace');
  Rejects<TSadRecord>(JSONSyntax,'{"Alpha"','cut after the key');
  Rejects<TSadRecord>(JSONSyntax,'{"Alpha":','cut after the colon');
  Rejects<TSadRecord>(JSONSyntax,'{"Alpha":1','cut after the value');
  Rejects<TSadRecord>(JSONSyntax,'{"Alpha":1,','cut after the comma');

  Rejects<TArray<integer>>(JSONSyntax,'[','cut after the bracket');
  Rejects<TArray<integer>>(JSONSyntax,'[1','cut after an element');
  Rejects<TArray<integer>>(JSONSyntax,'[1,','cut after a separator');

  Rejects<string>(JSONSyntax,'"unterminated','cut inside a string');
  Rejects<boolean>(JSONSyntax,'tru','cut inside a literal');
end;

procedure TSadPathsTest.TestBytesThatCannotStartAValue;
begin
  Rejects<TSadRecord>(JSONSyntax,'!','a byte that starts nothing');
  Rejects<TSadRecord>(JSONSyntax,'?{"Alpha":1}','junk before the object');
  Rejects<integer>(JSONSyntax,'@','a byte that starts nothing, scalar');
  Rejects<integer>(JSONSyntax,'undefined','an identifier that is not a literal');
  Rejects<boolean>(JSONSyntax,'True','JSON literals are lower case');
  Rejects<TSadRecord>(JSONSyntax,'{"Alpha":xyz}','junk where a value belongs');
end;

// each rejection ends ReadNumber in a different state
procedure TSadPathsTest.TestMalformedNumbers;
begin
  Rejects<integer>(JSONSyntax,'01','a leading zero');
  Rejects<integer>(JSONSyntax,'-','a lone minus');
  Rejects<integer>(JSONSyntax,'+1','a leading plus');
  Rejects<double>(JSONSyntax,'.5','no integer part');
  Rejects<double>(JSONSyntax,'1.','no fraction digits');
  Rejects<double>(JSONSyntax,'1e','no exponent at all');
  Rejects<double>(JSONSyntax,'1e+','a signed exponent with no digits');
  Rejects<double>(JSONSyntax,'1.2.3','two decimal points');
  Rejects<integer>(JSONSyntax,'0x10','hex is not JSON');
end;

procedure TSadPathsTest.TestMalformedStrings;
var
  backslash: string;
begin
  backslash:= '\';

  Rejects<string>(JSONSyntax,UTF8String('"a' + backslash + 'x b"'),'an escape that does not exist');
  Rejects<string>(JSONSyntax,UTF8String('"' + backslash + '"'),'a trailing backslash');
  Rejects<string>(JSONSyntax,UTF8String('"' + backslash + 'u00"'),'a short unicode escape');
  Rejects<string>(JSONSyntax,UTF8String('"' + backslash + 'uZZZZ"'),'a non-hex unicode escape');

  // a control character inside a string must be escaped
  Rejects<string>(JSONSyntax,UTF8String('"a' + #9 + 'b"'),'a raw tab inside a string');
  Rejects<string>(JSONSyntax,UTF8String('"a' + #10 + 'b"'),'a raw newline inside a string');
end;

procedure TSadPathsTest.TestBrokenStructure;
begin
  Rejects<TSadRecord>(JSONSyntax,'{"Alpha" 1}','a missing colon');
  Rejects<TSadRecord>(JSONSyntax,'{"Alpha":1,}','a trailing comma in an object');
  Rejects<TArray<integer>>(JSONSyntax,'[1,2,]','a trailing comma in an array');
  Rejects<TSadRecord>(JSONSyntax,'{Alpha:1}','an unquoted key');
  Rejects<TSadRecord>(JSONSyntax,'{"Alpha":1]','brackets that do not match');
  Rejects<TSadRecord>(JSONSyntax,'{"Alpha":1} trailing','garbage after the document');
  Rejects<integer>(JSONSyntax,'1 2','a second value after the first');
end;


//----------------------------------------------------------------------------
// the document is fine, the destination is wrong
//----------------------------------------------------------------------------

procedure TSadPathsTest.TestScalarGivenAnAggregate;
begin
  Rejects<integer>(JSONTypeMismatch,'{"a":1}','an object for an integer');
  Rejects<integer>(JSONTypeMismatch,'[1,2]','an array for an integer');
  Rejects<double>(JSONTypeMismatch,'[1.5]','an array for a double');
  Rejects<string>(JSONTypeMismatch,'{"a":"b"}','an object for a string');
  Rejects<boolean>(JSONTypeMismatch,'[true]','an array for a boolean');
  Rejects<TGUID>(JSONTypeMismatch,'["a"]','an array for a GUID');
end;

procedure TSadPathsTest.TestScalarGivenTheWrongScalar;
begin
  Rejects<integer>(JSONTypeMismatch,'"123"','a quoted number for an integer');
  Rejects<integer>(JSONTypeMismatch,'true','a boolean for an integer');
  Rejects<integer>(JSONTypeMismatch,'null','null for an integer');
  Rejects<double>(JSONTypeMismatch,'"1.5"','a quoted number for a double');
  Rejects<string>(JSONTypeMismatch,'123','a number for a string');
  Rejects<string>(JSONTypeMismatch,'true','a boolean for a string');
  Rejects<boolean>(JSONTypeMismatch,'"maybe"','a string for a boolean');
  Rejects<boolean>(JSONTypeMismatch,'1','a number for a boolean');
  // in quotes, true is a string
  Rejects<boolean>(JSONTypeMismatch,'"true"','a quoted true for a boolean');
  Rejects<boolean>(JSONTypeMismatch,'"false"','a quoted false for a boolean');
  // a well-formed number is a mismatch for a GUID, not a syntax error
  Rejects<TGUID>(JSONTypeMismatch,'123','a number for a GUID');
  Rejects<TGUID>(JSONTypeMismatch,'true','a boolean for a GUID');
end;

procedure TSadPathsTest.TestAggregateGivenAScalar;
begin
  Rejects<TSadRecord>(JSONTypeMismatch,'123','a number for a record');
  Rejects<TSadRecord>(JSONTypeMismatch,'"text"','a string for a record');
  Rejects<TSadRecord>(JSONTypeMismatch,'true','a boolean for a record');
  Rejects<TSadRecord>(JSONTypeMismatch,'[1,2]','an array for a record');
  Rejects<TSadRecord>(JSONTypeMismatch,'null','null for a record - it cannot be nil');
  Rejects<TArray<integer>>(JSONTypeMismatch,'123','a number for an array');
  Rejects<TArray<integer>>(JSONTypeMismatch,'{"a":1}','an object for an array');
  Rejects<TSadObject>(JSONTypeMismatch,'123','a number for an object');
  Rejects<TSadObject>(JSONTypeMismatch,'[1,2]','an array for an object');
  Rejects<TSadObject>(JSONTypeMismatch,'"text"','a string for an object');
  Rejects<TSadObject>(JSONTypeMismatch,'true','a boolean for an object');
end;

// both containers answer the wrong aggregate alike
procedure TSadPathsTest.TestContainerGivenTheWrongAggregate;
begin
  Rejects<TList<integer>>(JSONTypeMismatch,'{"a":1}','an object for a TList');
  Rejects<TList<integer>>(JSONTypeMismatch,'123','a number for a TList');
  Rejects<TDictionary<string,integer>>(JSONTypeMismatch,'[1,2]','an array for a TDictionary');
  Rejects<TDictionary<string,integer>>(JSONTypeMismatch,'123','a number for a TDictionary');
  Rejects<TStringList>(JSONTypeMismatch,'123','a number for a TStrings');
  Rejects<TStringList>(JSONTypeMismatch,'true','a boolean for a TStrings');
end;

// the right kind of value, but one the destination has no room for
procedure TSadPathsTest.TestValuesTheDestinationCannotHold;
begin
  Rejects<integer>(JSONTypeMismatch,'99999999999999999999','past the range of an int64');
  // one past each end of what the digit loop and its int64 conversion hold
  Rejects<int64>(JSONTypeMismatch,'9223372036854775808','one past High(Int64)');
  Rejects<int64>(JSONTypeMismatch,'-9223372036854775809','one past Low(Int64)');
  Rejects<UInt64>(JSONTypeMismatch,'18446744073709551616','one past High(UInt64)');
  Rejects<UInt64>(JSONTypeMismatch,'-1','a negative number for a UInt64');
  Rejects<double>(JSONTypeMismatch,'1e400','past the range of a double');
  // the destination's range decides, not extended's - 80 bits on Win32
  Rejects<single>(JSONTypeMismatch,'1e39','past the range of a single');
  Rejects<Currency>(JSONTypeMismatch,'1e20','past the range of a Currency');
  Rejects<Comp>(JSONTypeMismatch,'1e20','past the range of a Comp');
  Rejects<TColour>(JSONTypeMismatch,'"clMauve"','a name the enumeration does not have');
  // a name of the base type that the subrange does not have
  Rejects<TWarmColour>(JSONTypeMismatch,'"clBlue"','a name of the base type, outside the subrange');
  Rejects<TColour>(JSONTypeMismatch,'1','a number for an enumeration: only a name is one');
  Rejects<TGUID>(JSONTypeMismatch,'"not-a-guid"','text that is not a GUID');
  Rejects<TDateTime>(JSONTypeMismatch,'"not-a-date"','text that is not a date');

  // a dynamic array grows, a static one cannot
  Rejects<TFourInts>(JSONTypeMismatch,'[1,2,3,4,5]','five elements for a four-slot array');
  Rejects<TFourInts>(JSONTypeMismatch,'[1,2,3]','...and three, for the same reason');
  Rejects<TFourInts>(JSONTypeMismatch,'[]','...and none at all');
end;

// the code survives being handed up through ParseStruct
procedure TSadPathsTest.TestMismatchInsideAStruct;
begin
  Rejects<TSadRecord>(JSONTypeMismatch,'{"Alpha":"text"}','a string for an integer member');
  Rejects<TSadRecord>(JSONTypeMismatch,'{"Alpha":[1]}','an array for an integer member');
  Rejects<TSadNested>(JSONTypeMismatch,'{"Name":"n","Inner":{"Alpha":"text"}}','two levels down');
  Rejects<TSadNested>(JSONTypeMismatch,'{"Name":42}','a number for a string member');
end;


//----------------------------------------------------------------------------
// the type cannot be mapped at all
//----------------------------------------------------------------------------

// independent of the input: the element type has no handler, so the same code
// comes back whatever arrives - empty, null and nil included
procedure TSadPathsTest.TestUnmappableTypesOnDecode;
var
  procList: TList<TProc>;
  procDict: TDictionary<string,TProc>;
begin
  Rejects<TProcs>(JSONUnsupportedType,'[]','an array of method-pointers');
  Rejects<TProcs>(JSONUnsupportedType,'null','...null into one');
  Rejects<TPointers>(JSONUnsupportedType,'[]','an array of untyped pointers');
  Rejects<PInterface>(JSONUnsupportedType,'null','a pointer to an interface');
  Rejects<PSparse>(JSONUnsupportedType,'null','a pointer to a type without type info');
  Rejects<TSparsePair>(JSONUnsupportedType,'["spOne","spFive"]','a static array of an element without type info');

  Rejects<TList<TProc>>(JSONUnsupportedType,'[]','a list of method-pointers');
  Rejects<TList<TProc>>(JSONUnsupportedType,'null','...null into one');
  Rejects<TList<IInterface>>(JSONUnsupportedType,'[]','a list of interfaces');
  Rejects<TList<Pointer>>(JSONUnsupportedType,'[]','a list of untyped pointers');
  Rejects<TList<TSparse>>(JSONUnsupportedType,'[]','a list of an element without type info');

  Rejects<TDictionary<string,TProc>>(JSONUnsupportedType,'{}','a dictionary of method-pointers');
  Rejects<TDictionary<string,TProc>>(JSONUnsupportedType,'null','...null into one');
  Rejects<TDictionary<string,TSparse>>(JSONUnsupportedType,'{}','a dictionary of a value without type info');

  // refused before anything is done to it: a caller's container keeps its contents
  procList:= TList<TProc>.Create;
  procDict:= TDictionary<string,TProc>.Create;
  try
    procList.Add(nil);
    procDict.Add('k',nil);
    Assert.AreEqual(JSONUnsupportedType,JSON.Unmarshal('[]',procList),'into a list');
    Assert.AreEqual(1,integer(procList.Count),'...not emptied');
    Assert.AreEqual(JSONUnsupportedType,JSON.Unmarshal('{}',procDict),'into a dictionary');
    Assert.AreEqual(1,integer(procDict.Count),'...not emptied');
  finally
    procDict.Free;
    procList.Free;
  end;
end;

procedure TSadPathsTest.TestUnmappableTypesOnEncode;
var
  someProcs: TProcs;
  somePointers: TPointers;
  procList: TList<TProc>;
  sparseList: TList<TSparse>;
  sparsePair: TSparsePair;
  procDict: TDictionary<string,TProc>;
begin
  SetLength(someProcs,1);
  someProcs[0]:= nil;
  sparsePair[0]:= spOne;
  sparsePair[1]:= spFive;

  Refuses<TProcs>(JSONUnsupportedType,someProcs,'an array of method-pointers');
  Refuses<TProcs>(JSONUnsupportedType,nil,'...an empty one');
  Refuses<TPointers>(JSONUnsupportedType,somePointers,'an empty array of untyped pointers');
  Refuses<PInterface>(JSONUnsupportedType,nil,'a pointer to an interface');
  Refuses<PSparse>(JSONUnsupportedType,nil,'a pointer to a type without type info');
  Refuses<TSparsePair>(JSONUnsupportedType,sparsePair,'a static array of an element without type info');

  Refuses<TList<TProc>>(JSONUnsupportedType,nil,'a nil list of method-pointers');
  Refuses<TDictionary<string,TProc>>(JSONUnsupportedType,nil,'a nil dictionary of method-pointers');

  procList:= TList<TProc>.Create;
  sparseList:= TList<TSparse>.Create;
  procDict:= TDictionary<string,TProc>.Create;
  try
    Refuses<TList<TProc>>(JSONUnsupportedType,procList,'an empty list of method-pointers');
    Refuses<TList<TSparse>>(JSONUnsupportedType,sparseList,'an empty list of an element without type info');
    Refuses<TDictionary<string,TProc>>(JSONUnsupportedType,procDict,'an empty dictionary of method-pointers');

    procList.Add(nil);
    Refuses<TList<TProc>>(JSONUnsupportedType,procList,'a list holding one');
    procDict.Add('k',nil);
    Refuses<TDictionary<string,TProc>>(JSONUnsupportedType,procDict,'a dictionary holding one');
  finally
    procDict.Free;
    sparseList.Free;
    procList.Free;
  end;
end;

// the encode-side mirror: a value its own type cannot represent, which only a
// cast, uninitialised memory or arithmetic produces
type
  TColourSet = set of TColour;

procedure TSadPathsTest.TestValuesTheTypeCannotRepresent;
var
  someColour: TColour;
  someColours: TColourSet;
begin
  // a value past the last member has no name
  someColour:= TColour(7);
  Refuses<TColour>(JSONTypeMismatch,someColour,'an enumeration past its last member');

  // a set is stored in whole bytes: a spare bit set by a cast names no member
  someColours:= [];
  PByte(@someColours)^:= $FF;
  Refuses<TColourSet>(JSONTypeMismatch,someColours,'a set with a bit no member owns');

  // the RTL cannot format these
  Refuses<TDateTime>(JSONTypeMismatch,NaN,'a TDateTime that is NaN');
  Refuses<TDateTime>(JSONTypeMismatch,Infinity,'a TDateTime that is infinite');
  Refuses<TDateTime>(JSONTypeMismatch,MinDateTime-1,'a TDateTime before MinDateTime, the year 100');
  Refuses<TDateTime>(JSONTypeMismatch,MaxDateTime+1,'a TDateTime after MaxDateTime, the year 9999');
end;


//----------------------------------------------------------------------------
// contracts the return value does not show
//----------------------------------------------------------------------------

// an instance the library built is freed again on a failure. Rejects checks every
// class case; these are the ones that get partway in first. GetMemoryManagerState,
// because AllocMemCount reads 0 whatever leaks
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

procedure TSadPathsTest.TestFailedDecodeLeavesTheDestinationNil;
var
  list: TList<integer>;
  dict: TDictionary<string,integer>;
  strings: TStringList;
  obj: TSadObject;
  ptr: PSadRecord;
  mark: NativeInt;
begin
  list:= nil;
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('[1,"x"]'),list));
  Assert.IsTrue(list = nil,'TList, failing on the second element');

  list:= nil;
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(UTF8String('[1,'),list));
  Assert.IsTrue(list = nil,'TList, truncated after an element');

  dict:= nil;
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('{"a":"x"}'),dict));
  Assert.IsTrue(dict = nil,'TDictionary, failing on a value');

  strings:= nil;
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('123'),strings));
  Assert.IsTrue(strings = nil,'TStrings, wrong shape');

  obj:= nil;
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('{"Alpha":"x"}'),obj));
  Assert.IsTrue(obj = nil,'an object, failing on a member');

  // these fail on the structure between members, not inside one - a different way
  // out than every case above
  obj:= nil;
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(UTF8String('{"Alpha":1 "Beta":2}'),obj));
  Assert.IsTrue(obj = nil,'an object, missing the comma between members');

  obj:= nil;
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(UTF8String('{123:1}'),obj));
  Assert.IsTrue(obj = nil,'an object, given a key that is not a string');

  obj:= nil;
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(UTF8String('{"Alpha":1,'),obj));
  Assert.IsTrue(obj = nil,'an object, truncated after a comma');

  // a pointer target the library allocated: Beta is filled before Alpha fails, so
  // the block is finalized, not just freed. The first call warms the RTTI pool
  ptr:= nil;
  Assert.AreEqual(JSONTypeMismatch,
    JSON.Unmarshal(UTF8String('{"Beta":"filled first","Alpha":"x"}'),ptr));
  Assert.IsTrue(ptr = nil,'a pointer, failing after a string member');

  mark:= LiveBlocks;
  for var i:= 1 to 10 do begin
    ptr:= nil;
    JSON.Unmarshal(UTF8String('{"Beta":"filled first","Alpha":"x"}'),ptr);
  end;
  Assert.AreEqual<NativeInt>(0,LiveBlocks-mark,
    '...and releases the string it had already filled');
end;

// an instance the caller supplied is not ours to free, however the decode goes
procedure TSadPathsTest.TestFailureDoesNotFreeACallerSuppliedObject;
var
  list: TStringList;
  gotResult: TJSONResult;
begin
  list:= TStringList.Create;
  try
    list.Add('mine');

    gotResult:= JSON.Unmarshal(UTF8String('123'),list);
    Assert.AreEqual(JSONTypeMismatch,gotResult);

    // freed, this would be an access violation rather than a failed assertion
    Assert.IsNotNull(list,'a caller-supplied object must survive the failure');
    list.Add('still here');
    Assert.AreEqual('still here',list[list.Count-1]);
  finally
    list.Free;
  end;
end;

procedure TLiveCounted.AfterConstruction;
begin
  inherited;
  inc(Live);
end;

procedure TLiveCounted.BeforeDestruction;
begin
  dec(Live);
  inherited;
end;

// a container the library built takes the objects decoded into it along when it
// is freed - one level deep only, as docs/errors.md says
procedure TSadPathsTest.TestFailedContainerFreesWhatItHeld;
var
  list: TList<TLiveCounted>;
  dict: TDictionary<string,TLiveCounted>;
  owning: TObjectList<TLiveCounted>;
begin
  TLiveCounted.Live:= 0;

  list:= nil;
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('[{"Alpha":1},{"Alpha":"x"}]'),list));
  Assert.IsTrue(list = nil);
  Assert.AreEqual(0,TLiveCounted.Live,'a TList built here frees the object it held');

  dict:= nil;
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('{"a":{"Alpha":1},"b":{"Alpha":"x"}}'),dict));
  Assert.IsTrue(dict = nil);
  Assert.AreEqual(0,TLiveCounted.Live,'so does a TDictionary');

  // owns its elements already: freeing them as well would free them twice
  owning:= nil;
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('[{"Alpha":1},{"Alpha":"x"}]'),owning));
  Assert.IsTrue(owning = nil);
  Assert.AreEqual(0,TLiveCounted.Live,'a TObjectList frees them exactly once');

  // the caller's own list is the caller's, elements and all
  list:= TList<TLiveCounted>.Create;
  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('[{"Alpha":1},{"Alpha":"x"}]'),list));
  Assert.AreEqual(1,integer(list.Count),'a caller-supplied list keeps what was decoded');
  list[0].Free;
  list.Free;
end;

// a failed dynamic array holds what was decoded and nothing else - not the
// zero-filled slack it grows by
procedure TSadPathsTest.TestFailedArrayHoldsWhatWasDecoded;
var
  someArray: TArray<integer>;
  gotResult: TJSONResult;
begin
  someArray:= [90,91,92];
  gotResult:= JSON.Unmarshal(UTF8String('[1,"x"]'),someArray);
  Assert.AreEqual(JSONTypeMismatch,gotResult);
  Assert.AreEqual(1,integer(Length(someArray)),'one element was decoded before the failure');
  Assert.AreEqual(1,someArray[0]);
end;

// a property counts only in the direction it supports; a missing half makes it no
// member, not an error. A read-only class property is the exception - TestObjects
type
  THalfAccessible = class
  private
    fWritten: integer;
    function GetComputed: integer;
    procedure SetIncoming(v: integer);
  public
    Plain: integer;
    property Computed: integer read GetComputed;      // read-only
    property Incoming: integer write SetIncoming;     // write-only
    property Written: integer read fWritten;
  end;

function THalfAccessible.GetComputed: integer;
begin
  result:= 77;
end;

procedure THalfAccessible.SetIncoming(v: integer);
begin
  fWritten:= v;
end;

procedure TSadPathsTest.TestHalfAccessiblePropertiesAreSkipped;
var
  obj: THalfAccessible;
  gotResult: TJSONResult;
  gotJSON: UTF8String;
begin
  obj:= THalfAccessible.Create;
  try
    // encoding uses the readable half, so the write-only one is not there
    gotResult:= JSON.Marshal(obj,gotJSON);
    Assert.AreEqual(JSONOK,gotResult,'encode');
    Assert.AreEqual(UTF8String('{"Plain":0,"Computed":77,"Written":0}'),gotJSON);

    // decoding uses the writable half: the read-only names are skipped, nothing raises
    gotResult:= JSON.Unmarshal(
      UTF8String('{"Plain":1,"Computed":5,"Incoming":6,"Written":7}'),obj);
    Assert.AreEqual(JSONOK,gotResult,'decode must return a code, not raise');

    Assert.AreEqual(1,obj.Plain,'a plain field still decodes');
    Assert.AreEqual(6,obj.fWritten,'the write-only property was set');
    Assert.AreEqual(77,obj.Computed,'the read-only property was left alone');
  finally
    obj.Free;
  end;
end;

// a cycle has no end, so MaxDepth is all that stops a stack overflow - on the
// indented path too, which shares the writer's Depth
type
  TCycleNode = class
  public
    Name: string;
    Next: TCycleNode;
  end;

  TCycleBox = class
  public
    Items: TObjectList<TCycleBox>;
  end;

procedure TSadPathsTest.TestCyclicGraphStopsAtMaxDepth;
var
  first,second: TCycleNode;
  box: TCycleBox;
  deep: TJSONCodec;
  gotJSON: UTF8String;
  gotResult: TJSONResult;
begin
  // --- a node pointing at itself
  first:= TCycleNode.Create;
  try
    first.Name:= 'self';
    first.Next:= first;

    gotResult:= JSON.Marshal(first,gotJSON);
    Assert.AreEqual(JSONMaxDepthReached,gotResult,'a self-reference must terminate');

    gotResult:= JSON.MarshalIndent(first,'  ',gotJSON);
    Assert.AreEqual(JSONMaxDepthReached,gotResult,'...indented too - Depth rides on Indent');
  finally
    first.Next:= nil;
    first.Free;
  end;

  // --- two nodes pointing at each other
  first:= TCycleNode.Create;
  second:= TCycleNode.Create;
  try
    first.Name:= 'first';   first.Next:= second;
    second.Name:= 'second'; second.Next:= first;

    gotResult:= JSON.Marshal(first,gotJSON);
    Assert.AreEqual(JSONMaxDepthReached,gotResult,'a two-node cycle must terminate');

    // the config governs, not a constant
    deep:= TJSONCodec.Create(JSONDefaultConfig);
    try
      var cfg:= JSONDefaultConfig;
      cfg.MaxDepth:= 3;
      deep.Configure(cfg);

      gotResult:= deep.Marshal(first,gotJSON);
      Assert.AreEqual(JSONMaxDepthReached,gotResult,'MaxDepth 3 must stop it too');
    finally
      deep.Free;
    end;
  finally
    first.Next:= nil;
    second.Next:= nil;
    first.Free;
    second.Free;
  end;

  // --- a cycle through a container, so the array writer is on the path too
  box:= TCycleBox.Create;
  try
    box.Items:= TObjectList<TCycleBox>.Create(false);   // does not own what it holds
    box.Items.Add(box);

    gotResult:= JSON.Marshal(box,gotJSON);
    Assert.AreEqual(JSONMaxDepthReached,gotResult,'a cycle through a list must terminate');

    gotResult:= JSON.MarshalIndent(box,'  ',gotJSON);
    Assert.AreEqual(JSONMaxDepthReached,gotResult,'...indented too');
  finally
    box.Items.Clear;
    box.Items.Free;
    box.Free;
  end;
end;

// a dictionary takes part only with a string key - both ways, decided by the type
// before any pair, so an empty one of the wrong type fails as well
procedure TSadPathsTest.TestDictionaryWithANonStringKeyIsRejected;
var
  wrongKey: TDictionary<integer,string>;
  gotJSON: UTF8String;
  gotResult: TJSONResult;
begin
  // decoding
  Rejects<TDictionary<integer,string>>(JSONUnsupportedType,'{"1":"one"}',
    'an integer-keyed dictionary');

  // ...and empty: nothing reaches Add, the type alone decides
  Rejects<TDictionary<integer,string>>(JSONUnsupportedType,'{}',
    'an empty document, same dictionary');
  Rejects<TDictionary<integer,string>>(JSONUnsupportedType,'null',
    'null, same dictionary: the type decides');

  // encoding: the mirror, including the empty and the nil one
  Refuses<TDictionary<integer,string>>(JSONUnsupportedType,nil,'nil, integer-keyed');
  wrongKey:= TDictionary<integer,string>.Create;
  try
    gotResult:= JSON.Marshal(wrongKey,gotJSON);
    Assert.AreEqual(JSONUnsupportedType,gotResult,'empty, integer-keyed');

    wrongKey.Add(1,'one');
    gotResult:= JSON.Marshal(wrongKey,gotJSON);
    Assert.AreEqual(JSONUnsupportedType,gotResult,'populated, integer-keyed');
  finally
    wrongKey.Free;
  end;

  // a ShortString key is text, but Invoke wants its exact type: refused both ways
  Rejects<TDictionary<ShortString,integer>>(JSONUnsupportedType,'{"k":1}',
    'a ShortString-keyed dictionary');
  var shortKey:= TDictionary<ShortString,integer>.Create;
  try
    shortKey.Add('k',1);
    Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(shortKey,gotJSON),'populated, ShortString-keyed');
  finally
    shortKey.Free;
  end;

  // the supported shape still works
  var rightKey:= TDictionary<string,integer>.Create;
  try
    rightKey.Add('one',1);
    Assert.AreEqual(JSONOK,JSON.Marshal(rightKey,gotJSON));
    Assert.AreEqual(UTF8String('{"one":1}'),gotJSON);
  finally
    rightKey.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSadPathsTest);

end.
