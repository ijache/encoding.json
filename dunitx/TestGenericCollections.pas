unit TestGenericCollections;

interface

uses
  DUnitX.TestFramework,
  System.Classes,
  System.Generics.Collections,
  encoding.json;

type
  [TestFixture]
  TGenericCollectionsTest = class
  public
    [Test] procedure TestListsRoundTrip;
    [Test] procedure TestDecodeReplacesTheListContents;
    [Test] procedure TestListListenersSeeEveryDecodedElement;
    [Test] procedure TestDictionariesRoundTrip;
    [Test] procedure TestEncodeNilContainers;

    [Test] procedure TestListOfObjectsRoundTrip;
    [Test] procedure TestListOfRecordPointersRoundTrip;
    [Test] procedure TestObjectListOwnsWhatItDecodes;
    [Test] procedure TestNestedContainersRoundTrip;

  end;

implementation

uses
  TestHelpers;

type TAliasedListType = TList<integer>;

type
  TSubClassedListType<T> = class(TList<T>)
  public
  end;

  // counts what Notify is told is added, whether by override or by OnNotify
  TCountingList = class(TList<integer>)
  protected
    procedure Notify(const Item: integer; Action: TCollectionNotification); override;
  public
    Added: integer;
  end;

  TAddCounter = class
  public
    Added: integer;
    procedure Count(Sender: TObject; const Item: integer; Action: TCollectionNotification);
  end;

procedure TCountingList.Notify(const Item: integer; Action: TCollectionNotification);
begin
  inherited;
  if Action = cnAdded then inc(Added);
end;

procedure TAddCounter.Count(Sender: TObject; const Item: integer; Action: TCollectionNotification);
begin
  if Action = cnAdded then inc(Added);
end;



type
  TSomeRecord = record
    IntValue: integer;
    StringValue: string;
    class operator Equal(const a,b: TSomeRecord): boolean;
  end;

class operator TSomeRecord.Equal(const a, b: TSomeRecord): boolean;
begin
  result:= (a.IntValue = b.IntValue) and (a.StringValue = b.StringValue);
end;

function SomeRecord(i: integer; s: string): TSomeRecord;
begin
  result.IntValue:= i;
  result.StringValue:= s;
end;

type
  TSomeObject = class
  public
    IntValue: integer;
    StringValue: string;
    constructor Create(i: integer; s: string);
    function IsEqual(const a: TSomeObject): boolean;
  end;

constructor TSomeObject.Create(i: integer; s: string);
begin
  self.IntValue:= i;
  self.StringValue:= s;
end;

function TSomeObject.IsEqual(const a: TSomeObject): boolean;
begin
  result:= (a.IntValue = self.IntValue) and (a.StringValue = self.StringValue);
end;

// a TList is an array, whatever it is called: plain, through an alias, or a
// subclass - the handler is registered for the generic name and its ancestry
procedure TGenericCollectionsTest.TestListsRoundTrip;
var
  ints: TList<integer>;
  aliased: TAliasedListType;
  subclassed: TSubClassedListType<integer>;
  strings: TList<string>;
  records: TList<TSomeRecord>;
begin
  ints:= TList<integer>.Create;
  ints.AddRange([1,2,3,4]);
  Check.RoundTrips<TList<integer>>(ints,'[1,2,3,4]','integers');
  ints.Clear;
  Check.RoundTrips<TList<integer>>(ints,'[]','empty');
  ints.Free;

  aliased:= TAliasedListType.Create;
  aliased.AddRange([1,2,3,4]);
  Check.RoundTrips<TAliasedListType>(aliased,'[1,2,3,4]','an alias');
  aliased.Free;

  subclassed:= TSubClassedListType<integer>.Create;
  subclassed.AddRange([1,2,3,4]);
  Check.RoundTrips<TSubClassedListType<integer>>(subclassed,'[1,2,3,4]','a subclass');
  subclassed.Free;

  strings:= TList<string>.Create;
  strings.AddRange(['Paul','Ringo','George','John']);
  Check.RoundTrips<TList<string>>(strings,'["Paul","Ringo","George","John"]','strings');
  strings.Free;

  records:= TList<TSomeRecord>.Create;
  records.Add(SomeRecord(1,'Paul'));
  records.Add(SomeRecord(2,'Ringo'));
  Check.RoundTrips<TList<TSomeRecord>>(records,
    '[{"IntValue":1,"StringValue":"Paul"},{"IntValue":2,"StringValue":"Ringo"}]','records');
  records.Free;
end;

// a list the caller holds is cleared before it is filled
procedure TGenericCollectionsTest.TestDecodeReplacesTheListContents;
var
  l: TList<integer>;
begin
  l:= TList<integer>.Create;
  l.Add(1234);
  Assert.AreEqual(JSONOK,JSON.Unmarshal('[1,2,3,4]',l));
  Check.Encodes<TList<integer>>(l,'[1,2,3,4]');
  l.Free;
end;

// a plain list is filled at once, which notifies nobody - so a list somebody
// listens to, by an overridden Notify or by OnNotify, still gets every Add
procedure TGenericCollectionsTest.TestListListenersSeeEveryDecodedElement;
var
  overridden: TCountingList;
  plain: TList<integer>;
  counter: TAddCounter;
begin
  overridden:= TCountingList.Create;
  Assert.AreEqual(JSONOK,JSON.Unmarshal('[1,2,3]',overridden));
  Assert.AreEqual(3,overridden.Added,'an overridden Notify');
  overridden.Free;

  counter:= TAddCounter.Create;
  plain:= TList<integer>.Create;
  plain.OnNotify:= counter.Count;
  Assert.AreEqual(JSONOK,JSON.Unmarshal('[1,2,3]',plain));
  Assert.AreEqual(3,counter.Added,'OnNotify');
  plain.Free;
  counter.Free;
end;

// a dictionary enumerates in hash order; its keys always go out sorted - by
// the rule record members sort by - so the text does not depend on the RTL
procedure TGenericCollectionsTest.TestDictionariesRoundTrip;
const
  OBJECTS_JSON = '{"A":{"IntValue":1,"StringValue":"Paul"},"B":{"IntValue":2,"StringValue":"Ringo"}}';
var
  names: TDictionary<string,string>;
  ordinal: TDictionary<string,integer>;
  records: TDictionary<string,TSomeRecord>;
  objects,got: TDictionary<string,TSomeObject>;
begin
  names:= TDictionary<string,string>.Create;
  names.Add('Paul','McCartney');
  names.Add('Ringo','Starr');
  names.Add('George','Harrison');
  names.Add('John','Lennon');
  Check.RoundTrips<TDictionary<string,string>>(names,
    '{"George":"Harrison","John":"Lennon","Paul":"McCartney","Ringo":"Starr"}','strings');
  names.Free;

  ordinal:= TDictionary<string,integer>.Create;
  ordinal.Add('zulu',1);
  ordinal.Add('alpha',2);
  ordinal.Add('mike',3);
  ordinal.Add('a',4);
  ordinal.Add('Z',5);
  Check.RoundTrips<TDictionary<string,integer>>(ordinal,
    '{"Z":5,"a":4,"alpha":2,"mike":3,"zulu":1}','ordinal: "Z" before "a", a prefix first');
  ordinal.Free;

  records:= TDictionary<string,TSomeRecord>.Create;
  records.Add('B',SomeRecord(2,'Ringo'));
  records.Add('A',SomeRecord(1,'Paul'));
  Check.RoundTrips<TDictionary<string,TSomeRecord>>(records,OBJECTS_JSON,'records');
  records.Free;

  // a TDictionary does not own its values, so these are the test's to free
  objects:= TDictionary<string,TSomeObject>.Create;
  objects.Add('B',TSomeObject.Create(2,'Ringo'));
  objects.Add('A',TSomeObject.Create(1,'Paul'));
  Check.Encodes<TDictionary<string,TSomeObject>>(objects,OBJECTS_JSON,'objects');
  got:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(OBJECTS_JSON,got));
  Check.Encodes<TDictionary<string,TSomeObject>>(got,OBJECTS_JSON,'objects, decoded');
  for var o in objects.Values do o.Free;
  for var o in got.Values do o.Free;
  objects.Free;
  got.Free;
end;

// each container formatter runs instead of FormatStruct, so each handles nil itself
procedure TGenericCollectionsTest.TestEncodeNilContainers;
var
  gotJSON: string;
  gotResult: TJSONResult;
  nilList: TList<integer>;
  nilDict: TDictionary<string,integer>;
  nilStrings: TStringlist;
begin
  nilList:= nil;
  gotResult:= JSON.Marshal(nilList,gotJSON);
  Assert.AreEqual(JSONOK,gotResult,'nil TList');
  Assert.AreEqual('null',gotJSON,'nil TList');

  nilDict:= nil;
  gotResult:= JSON.Marshal(nilDict,gotJSON);
  Assert.AreEqual(JSONOK,gotResult,'nil TDictionary');
  Assert.AreEqual('null',gotJSON,'nil TDictionary');

  nilStrings:= nil;
  gotResult:= JSON.Marshal(nilStrings,gotJSON);
  Assert.AreEqual(JSONOK,gotResult,'nil TStringlist');
  Assert.AreEqual('null',gotJSON,'nil TStringlist');
end;

// a TList does not own its elements, so every object here is the test's to
// free - the ones it built and the ones the decode built
procedure TGenericCollectionsTest.TestListOfObjectsRoundTrip;
var
  someList,gotList: TList<TSomeObject>;
  gotJSON: string;
begin
  someList:= TList<TSomeObject>.Create;
  someList.Add(TSomeObject.Create(1,'Paul'));
  someList.Add(TSomeObject.Create(2,'Ringo'));

  Assert.AreEqual(JSONOK,JSON.Marshal(someList,gotJSON));
  Assert.AreEqual('[{"IntValue":1,"StringValue":"Paul"},{"IntValue":2,"StringValue":"Ringo"}]',gotJSON,false);

  gotList:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,gotList));
  Assert.AreEqual(2,integer(gotList.Count));
  Assert.IsTrue(someList[0].IsEqual(gotList[0]),'first element');
  Assert.IsTrue(someList[1].IsEqual(gotList[1]),'second element');

  for var o in someList do o.Free;
  for var o in gotList do o.Free;
  someList.Free;
  gotList.Free;
end;

type
  PSomeRecord = ^TSomeRecord;

// an element type that is a pointer: encoding follows it, decoding allocates
// a target per element the way New would
procedure TGenericCollectionsTest.TestListOfRecordPointersRoundTrip;
var
  someList,gotList: TList<PSomeRecord>;
  first,second: TSomeRecord;
  gotJSON: string;
begin
  first:= SomeRecord(1,'Paul');
  second:= SomeRecord(2,'Ringo');
  someList:= TList<PSomeRecord>.Create;
  someList.Add(@first);
  someList.Add(@second);

  Assert.AreEqual(JSONOK,JSON.Marshal(someList,gotJSON));
  Assert.AreEqual('[{"IntValue":1,"StringValue":"Paul"},{"IntValue":2,"StringValue":"Ringo"}]',gotJSON,false);

  gotList:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,gotList));
  Assert.AreEqual(2,integer(gotList.Count));
  Assert.IsTrue(gotList[0]^ = first,'first element');
  Assert.IsTrue(gotList[1]^ = second,'second element');

  for var p in gotList do Dispose(p);
  someList.Free;
  gotList.Free;
end;

// a decoded TObjectList owns its objects, as one made with Create does
procedure TGenericCollectionsTest.TestObjectListOwnsWhatItDecodes;
var
  gotList: TObjectList<TSomeObject>;
  gotJSON: string;
begin
  gotList:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal('[{"IntValue":1,"StringValue":"Paul"}]',gotList));
  Assert.IsTrue(gotList.OwnsObjects,'owns its elements');
  Assert.AreEqual(1,integer(gotList.Count));
  Assert.AreEqual(1,gotList[0].IntValue);

  Assert.AreEqual(JSONOK,JSON.Marshal(gotList,gotJSON));
  Assert.AreEqual('[{"IntValue":1,"StringValue":"Paul"}]',gotJSON,false,'and encodes like any TList');

  gotList.Free;
end;

// containers inside containers, and dynamic arrays on either side of a TList.
// every inner container the decode built is the test's to free.
procedure TGenericCollectionsTest.TestNestedContainersRoundTrip;
var
  listOfLists,gotListOfLists: TList<TList<integer>>;
  dictOfLists,gotDictOfLists: TDictionary<string,TList<integer>>;
  listOfArrays,gotListOfArrays: TList<TArray<integer>>;
  arrayOfLists,gotArrayOfLists: TArray<TList<integer>>;
  gotJSON: string;
begin
  listOfLists:= TList<TList<integer>>.Create;
  listOfLists.Add(TList<integer>.Create);
  listOfLists[0].AddRange([1,2]);
  listOfLists.Add(TList<integer>.Create);
  Assert.AreEqual(JSONOK,JSON.Marshal(listOfLists,gotJSON));
  Assert.AreEqual('[[1,2],[]]',gotJSON);
  gotListOfLists:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,gotListOfLists));
  Assert.AreEqual(2,integer(gotListOfLists.Count),'list of lists');
  Assert.AreEqual(2,gotListOfLists[0][1]);
  Assert.AreEqual(0,integer(gotListOfLists[1].Count),'an empty inner list is a list, not nil');
  for var l in listOfLists do l.Free;
  for var l in gotListOfLists do l.Free;
  listOfLists.Free;
  gotListOfLists.Free;

  dictOfLists:= TDictionary<string,TList<integer>>.Create;
  dictOfLists.Add('a',TList<integer>.Create);
  dictOfLists['a'].Add(5);
  Assert.AreEqual(JSONOK,JSON.Marshal(dictOfLists,gotJSON));
  Assert.AreEqual('{"a":[5]}',gotJSON);
  gotDictOfLists:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,gotDictOfLists));
  Assert.AreEqual(5,gotDictOfLists['a'][0],'dictionary of lists');
  for var l in dictOfLists.Values do l.Free;
  for var l in gotDictOfLists.Values do l.Free;
  dictOfLists.Free;
  gotDictOfLists.Free;

  listOfArrays:= TList<TArray<integer>>.Create;
  listOfArrays.Add([1,2]);
  listOfArrays.Add([]);
  Assert.AreEqual(JSONOK,JSON.Marshal(listOfArrays,gotJSON));
  Assert.AreEqual('[[1,2],[]]',gotJSON);
  gotListOfArrays:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,gotListOfArrays));
  Assert.AreEqual(2,integer(Length(gotListOfArrays[0])),'list of arrays');
  Assert.AreEqual(0,integer(Length(gotListOfArrays[1])));
  listOfArrays.Free;
  gotListOfArrays.Free;

  SetLength(arrayOfLists,1);
  arrayOfLists[0]:= TList<integer>.Create;
  arrayOfLists[0].Add(9);
  Assert.AreEqual(JSONOK,JSON.Marshal(arrayOfLists,gotJSON));
  Assert.AreEqual('[[9]]',gotJSON);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,gotArrayOfLists));
  Assert.AreEqual(9,gotArrayOfLists[0][0],'array of lists');
  arrayOfLists[0].Free;
  gotArrayOfLists[0].Free;
end;

initialization
  TDUnitX.RegisterTestFixture(TGenericCollectionsTest);

end.
