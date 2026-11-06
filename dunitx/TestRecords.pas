unit TestRecords;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  encoding.json;

type
  [TestFixture]
  TRecordsTest = class
  public
    [Test] procedure TestRoundTrip;
    [Test] procedure TestThroughAPointer;
    [Test] procedure TestMembersWithoutTypeInfoAreRefused;

    [Test] procedure TestFieldlessRecordRoundTrips;
    [Test] procedure TestManagedRecordsRoundTrip;

    [Test] procedure TestNestedPointersRoundTrip;
    [Test] procedure TestPointerToASharedString;
    [Test] procedure TestContainerMemberRoundTrip;
  end;

implementation

uses
  System.Generics.Collections,
  TestHelpers;


type
  TBasicRecord = record
    StringField: string;
    IntField: integer;
    FloatField: double;
    BoolField: boolean;
    class operator Equal(const a,b: TBasicRecord): boolean;
  end;
  PBasicRecord = ^TBasicRecord;

class operator TBasicRecord.Equal(const a, b: TBasicRecord): boolean;
begin
  result:= (a.StringField = b.StringField) and (a.IntField = b.IntField) and (a.FloatField = b.FloatField) and (a.BoolField = b.BoolField);
end;

type
  TNestedRecord = record
    TopLevel: string;
    Nested: TBasicRecord;
  end;

const
  BASIC_JSON = '{"StringField":"a string","IntField":42,"FloatField":3.14159,"BoolField":true}';

function BasicRecord: TBasicRecord;
begin
  result.StringField:= 'a string';
  result.IntField:= 42;
  result.FloatField:= 3.14159;
  result.BoolField:= true;
end;

procedure TRecordsTest.TestRoundTrip;
var
  nested: TNestedRecord;
begin
  Check.RoundTrips<TBasicRecord>(BasicRecord,BASIC_JSON,'flat');

  nested.TopLevel:= 'top level';
  nested.Nested:= BasicRecord;
  Check.RoundTrips<TNestedRecord>(nested,'{"TopLevel":"top level","Nested":'+BASIC_JSON+'}','nested');
end;

// followed on the way out; on the way in a nil pointer gets a target the way New
// would allocate it
procedure TRecordsTest.TestThroughAPointer;
var
  someRecord: TBasicRecord;
  p: PBasicRecord;
begin
  someRecord:= BasicRecord;
  p:= @someRecord;
  Check.Encodes<PBasicRecord>(p,BASIC_JSON);

  someRecord:= Default(TBasicRecord);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(BASIC_JSON,p),'into the record it points at');
  Assert.IsTrue(someRecord = BasicRecord);

  p:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(BASIC_JSON,p),'through a nil pointer');
  Assert.IsNotNull(p);
  Assert.IsTrue(p^ = BasicRecord);
  Dispose(p);
end;

// Delphi emits no type info for these, so the member has no type to map
type
  TSparse = (spOne = 1, spFive = 5);
  TSmallSet = set of 8..15;

  TWithStaticArray = record
    SomeString: string;
    SomeArray: array[0..3] of Integer;
  end;

  TWithSubrangeSet = record
    SomeString: string;
    SomeSet: set of 8..15;
  end;

  TWithSparseEnum = record
    SomeString: string;
    SomeEnum: TSparse;
  end;

  TWithSkippedStaticArray = record
    SomeString: string;
    [JSON('-')] SomeArray: array[0..3] of Integer;
  end;

  // Delphi leaves a property of such a type out of RTTI altogether, so unlike
  // a field it cannot be refused: it is not seen
  TWithSparseProperty = class
  private
    FSomeEnum: TSparse;
    FSomeSet: TSmallSet;
  public
    property SomeEnum: TSparse read FSomeEnum write FSomeEnum;
    property SomeSet: TSmallSet read FSomeSet write FSomeSet;
  end;

// refused, not skipped: a reader expects these in the document - and decoding
// refuses only a document that names one
procedure TRecordsTest.TestMembersWithoutTypeInfoAreRefused;
var
  gotJSON: string;
  someArray: TWithStaticArray;
  someSet: TWithSubrangeSet;
  someEnum: TWithSparseEnum;
  skipped: TWithSkippedStaticArray;
  someObject: TWithSparseProperty;
begin
  someArray:= Default(TWithStaticArray);
  someSet:= Default(TWithSubrangeSet);
  someEnum:= Default(TWithSparseEnum);
  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(someArray,gotJSON),'an inline static array');
  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(someSet,gotJSON),'a set over a subrange');
  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(someEnum,gotJSON),'an enumeration with explicit values');

  Assert.AreEqual(JSONUnsupportedType,JSON.Unmarshal('{"SomeArray":[1,2,3,4]}',someArray),'decoding the array');
  Assert.AreEqual(JSONUnsupportedType,JSON.Unmarshal('{"SomeSet":[]}',someSet),'decoding the set');
  Assert.AreEqual(JSONUnsupportedType,JSON.Unmarshal('{"SomeEnum":"spOne"}',someEnum),'decoding the enumeration');
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"SomeString":"s"}',someArray),'a document that does not name it');
  Assert.AreEqual('s',someArray.SomeString);

  someObject:= TWithSparseProperty.Create;
  try
    Assert.AreEqual(JSONOK,JSON.Marshal(someObject,gotJSON),'properties without type info');
    Assert.AreEqual('{}',gotJSON,'...is not seen');
  finally
    someObject.Free;
  end;

  // the attribute opts out
  skipped:= Default(TWithSkippedStaticArray);
  skipped.SomeString:= 'test';
  skipped.SomeArray[0]:= 1;
  Assert.AreEqual(JSONOK,JSON.Marshal(skipped,gotJSON));
  Assert.AreEqual('{"SomeString":"test"}',gotJSON);
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"SomeString":"x","SomeArray":[9,9,9,9]}',skipped));
  Assert.AreEqual(1,skipped.SomeArray[0],'nothing decoded into the skipped member');
end;

// no members at all: nothing else marshals such a type, and its failure would be
// an exception, so calling it is the test
type
  TFieldless = record
  end;

  // one strict private field: has RTTI but no *visible* member, which reaches
  // the zero-member path from the other side
  TAllPrivate = record
  strict private
    fHidden: integer;
  end;

procedure TRecordsTest.TestFieldlessRecordRoundTrips;
var
  gotResult: TJSONResult;
  gotJSON: string;
  empty: TFieldless;
  hidden: TAllPrivate;
begin
  gotResult:= JSON.Marshal(empty,gotJSON);
  Assert.AreEqual(JSONOK,gotResult,'marshal must return a code, not raise');
  Assert.AreEqual('{}',gotJSON);

  gotResult:= JSON.Unmarshal(gotJSON,empty);
  Assert.AreEqual(JSONOK,gotResult,'and it has to read back');

  gotResult:= JSON.Marshal(hidden,gotJSON);
  Assert.AreEqual(JSONOK,gotResult,'a record whose only field is invisible');
  Assert.AreEqual('{}',gotJSON);
end;

// a managed record (tkMRecord), and anything holding one, is a struct like any other
type
  TManaged = record
    A: integer;
    class operator Initialize(out r: TManaged);
  end;

  TManagedHolder = record
    M: TManaged;
    B: integer;
  end;

  PManaged = ^TManaged;
  PManagedHolder = ^TManagedHolder;

class operator TManaged.Initialize(out r: TManaged);
begin
  r.A:= -1;
end;

procedure TRecordsTest.TestManagedRecordsRoundTrip;
var
  m,gotM: TManaged;
  h,gotH: TManagedHolder;
  gotJSON: string;
  pm: PManaged;
  ph: PManagedHolder;
begin
  m.A:= 7;
  Assert.AreEqual(JSONOK,JSON.Marshal(m,gotJSON),'a managed record');
  Assert.AreEqual('{"A":7}',gotJSON);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,gotM));
  Assert.AreEqual(7,gotM.A);

  h.M.A:= 7;
  h.B:= 2;
  Assert.AreEqual(JSONOK,JSON.Marshal(h,gotJSON),'a record holding one');
  Assert.AreEqual('{"M":{"A":7},"B":2}',gotJSON);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,gotH));
  Assert.AreEqual(7,gotH.M.A);
  Assert.AreEqual(2,gotH.B);

  // decoding merges, so a member the document does not name keeps what it held
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"B":3}',gotH));
  Assert.AreEqual(7,gotH.M.A,'left alone');

  // an allocated target runs the operator too: A must be -1, not 0 - reached through
  // a holder without one
  pm:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{}',pm));
  try
    Assert.AreEqual(-1,pm.A,'a pointer target is initialised by its operator');
  finally
    Dispose(pm);
  end;

  ph:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"B":3}',ph));
  try
    Assert.AreEqual(-1,ph.M.A,'...and so is a record inside it');
    Assert.AreEqual(3,ph.B);
  finally
    Dispose(ph);
  end;
end;

type
  TPointerMembers = record
    PI: PInteger;
    PS: PString;
    PR: PBasicRecord;
  end;

  TNestedPointers = record
    Name: string;
    Inner: TPointerMembers;
  end;

// typed pointers one record down; nil goes out as null and comes back nil
procedure TRecordsTest.TestNestedPointersRoundTrip;
var
  want,got: TNestedPointers;
  someInt: integer;
  someString: string;
  someRecord: TBasicRecord;
  gotJSON: string;
begin
  someInt:= 42;
  someString:= 'pointed at';
  someRecord.StringField:= 'inner';
  someRecord.IntField:= 7;
  someRecord.FloatField:= 0.5;
  someRecord.BoolField:= true;

  want.Name:= 'outer';
  want.Inner.PI:= @someInt;
  want.Inner.PS:= @someString;
  want.Inner.PR:= @someRecord;

  Assert.AreEqual(JSONOK,JSON.Marshal(want,gotJSON));
  Assert.AreEqual('{"Name":"outer","Inner":{"PI":42,"PS":"pointed at",'+
    '"PR":{"StringField":"inner","IntField":7,"FloatField":0.5,"BoolField":true}}}',gotJSON,false);

  got:= Default(TNestedPointers);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,got));
  Assert.AreEqual('outer',got.Name);
  Assert.AreEqual(42,got.Inner.PI^);
  Assert.AreEqual('pointed at',got.Inner.PS^,false);
  Assert.IsTrue(got.Inner.PR^ = someRecord,'the record behind the pointer');
  Dispose(got.Inner.PI);
  Dispose(got.Inner.PS);
  Dispose(got.Inner.PR);

  want.Inner:= Default(TPointerMembers);
  Assert.AreEqual(JSONOK,JSON.Marshal(want,gotJSON));
  Assert.AreEqual('{"Name":"outer","Inner":{"PI":null,"PS":null,"PR":null}}',gotJSON);

  got:= Default(TNestedPointers);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,got));
  Assert.IsTrue((got.Inner.PI = nil) and (got.Inner.PS = nil) and (got.Inner.PR = nil),'nil comes back as nil');
end;

// decoding through a PString assigns, so text another variable shares stays put
procedure TRecordsTest.TestPointerToASharedString;
var
  someString,sharedString: string;
  holder: TPointerMembers;
begin
  // built at runtime, so it is a counted heap string and not a constant
  someString:= 'old ' + IntToStr(1);
  sharedString:= someString;

  holder:= Default(TPointerMembers);
  holder.PS:= @someString;
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"PS":"new"}',holder));

  Assert.IsTrue(holder.PS = @someString,'a live pointer is written through, not replaced');
  Assert.AreEqual('new',someString,false);
  Assert.AreEqual('old 1',sharedString,false,'the other holder keeps the old text');
end;

type
  TListHolder = record
    Name: string;
    Items: TList<integer>;
  end;

// a container as a record member: a nil one is built by the decode, the way
// an object member is, and is then the caller's to free
procedure TRecordsTest.TestContainerMemberRoundTrip;
var
  want,got: TListHolder;
  gotJSON: string;
begin
  want.Name:= 'n';
  want.Items:= TList<integer>.Create;
  want.Items.AddRange([1,2,3]);

  Assert.AreEqual(JSONOK,JSON.Marshal(want,gotJSON));
  Assert.AreEqual('{"Name":"n","Items":[1,2,3]}',gotJSON);

  got:= Default(TListHolder);
  Assert.AreEqual(JSONOK,JSON.Unmarshal(gotJSON,got));
  Assert.IsNotNull(got.Items,'the decode built the list');
  Assert.AreEqual(3,integer(got.Items.Count));
  Assert.AreEqual(3,got.Items[2]);

  want.Items.Free;
  got.Items.Free;
end;

initialization
  TDUnitX.RegisterTestFixture(TRecordsTest);

end.
