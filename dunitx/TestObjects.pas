unit TestObjects;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  encoding.json;

type
  [TestFixture]
  TObjectsTest = class
  public
    [Test] procedure TestRoundTrip;
    [Test] procedure TestClassPropertiesAreFilledInPlace;
    [Test] procedure TestNullIntoAClassProperty;
    [Test] procedure TestRedeclaredMembersHideTheAncestors;
  end;

implementation

uses
  TestHelpers;

type
  TBasicObject = class
  private
    fStringProp: string;
  public
    StringField: string;
    IntField: integer;
    FloatField: double;
    BoolField: boolean;
    property StringProperty: string read fStringProp write fStringProp;
  end;

const
  BASIC_JSON = '{"StringField":"a string","IntField":42,"FloatField":3.14159,'+
               '"BoolField":true,"StringProperty":"a string property"}';

// fields and a property. RoundTrips decodes into nil, so the library builds
// the instance; decoding into an existing one fills that one instead.
procedure TObjectsTest.TestRoundTrip;
var
  o,got: TBasicObject;
begin
  o:= TBasicObject.Create;
  o.StringField:= 'a string';
  o.IntField:= 42;
  o.FloatField:= 3.14159;
  o.BoolField:= true;
  o.StringProperty:= 'a string property';
  Check.RoundTrips<TBasicObject>(o,BASIC_JSON);
  o.Free;

  got:= TBasicObject.Create;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(BASIC_JSON,got));
  Check.Encodes<TBasicObject>(got,BASIC_JSON,'into an existing instance');
  got.Free;
end;

type
  TPropertyOwner = class
  private
    fItems: TList<integer>;
    fLines: TStringList;
    fNothing: TStringList;
    fSetterCalls: integer;
    procedure SetLines(const value: TStringList);
  public
    constructor Create;
    destructor Destroy; override;
    // read-only: the reference is fixed, the contents are meant to be filled
    property Items: TList<integer> read fItems;
    // a setter that copies, the usual VCL pattern
    property Lines: TStringList read fLines write SetLines;
    // read-only and nil: there is nothing to fill
    property Nothing: TStringList read fNothing;
  end;

constructor TPropertyOwner.Create;
begin
  fItems:= TList<integer>.Create;
  fLines:= TStringList.Create;
end;

destructor TPropertyOwner.Destroy;
begin
  fItems.Free;
  fLines.Free;
  inherited;
end;

// copies into the instance it has; takes ownership only when it has none, so
// the test does not leak the fresh instance the library hands it then
procedure TPropertyOwner.SetLines(const value: TStringList);
begin
  inc(fSetterCalls);
  if value = nil then
    FreeAndNil(fLines)
  else if fLines = nil then
    fLines:= value
  else
    fLines.Assign(value);
end;

// A class-typed property is decoded into the instance its getter returns, as a
// field is: read-only or not, and without calling the setter.
procedure TObjectsTest.TestClassPropertiesAreFilledInPlace;
var
  o,back: TPropertyOwner;
  items: TList<integer>;
  lines: TStringList;
  s: UTF8String;
begin
  o:= TPropertyOwner.Create;
  o.Items.Add(9);
  items:= o.Items;
  lines:= o.Lines;

  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"Items":[1,2,3],"Lines":["a","b"],"Nothing":["x"]}'),o));
  Assert.IsTrue(o.Items = items,'the read-only list is the same instance');
  Assert.AreEqual(3,integer(o.Items.Count),'and holds what the document says, nothing else');
  Assert.AreEqual(1,o.Items[0]);
  Assert.IsTrue(o.Lines = lines,'the list behind the setter is the same instance');
  Assert.AreEqual(2,o.Lines.Count);
  Assert.AreEqual('b',o.Lines[1],false);
  Assert.AreEqual(0,o.fSetterCalls,'the setter is not called');
  Assert.IsTrue(o.Nothing = nil,'a read-only property holding nil is skipped');

  // which is what makes a read-only list round-trip
  Assert.AreEqual(JSONOK,JSON.Marshal(o,s));
  back:= TPropertyOwner.Create;
  Assert.AreEqual(JSONOK,JSON.Unmarshal(s,back));
  Assert.AreEqual(3,integer(back.Items.Count));
  Assert.AreEqual(2,back.Lines.Count);

  back.Free;
  o.Free;
end;

// null must not free an instance its owner still holds. Without a setter it
// is refused; with one, the setter gets nil and decides.
procedure TObjectsTest.TestNullIntoAClassProperty;
var
  o: TPropertyOwner;
  items: TList<integer>;
begin
  o:= TPropertyOwner.Create;
  items:= o.Items;

  Assert.AreEqual(JSONTypeMismatch,JSON.Unmarshal(UTF8String('{"Items":null}'),o),'null into a read-only property');
  Assert.IsTrue(o.Items = items,'the instance is neither freed nor dropped');

  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"Lines":null}'),o));
  Assert.AreEqual(1,o.fSetterCalls,'null goes to the setter');
  Assert.IsTrue(o.Lines = nil);

  // with the getter returning nil, a fresh instance is built for the setter
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"Lines":["c"]}'),o));
  Assert.AreEqual(2,o.fSetterCalls);
  Assert.AreEqual(1,o.Lines.Count);

  o.Free;
end;

type
  THidingBase = class
  public
    X: integer;
    Y: integer;
    Z: integer;
  end;

  // hiding is the point here
  {$WARN HIDING_MEMBER OFF}
  THidingChild = class(THidingBase)
  private
    fY: string;
  public
    X: string;                              // a field hides a field
    property Y: string read fY write fY;    // a property hides a field
  end;
  {$WARN HIDING_MEMBER ON}

// a member a descendant redeclares hides the ancestor's, as in Delphi
procedure TObjectsTest.TestRedeclaredMembersHideTheAncestors;
var
  o: THidingChild;
  s: string;
begin
  o:= THidingChild.Create;
  o.X:= 'a';
  o.Y:= 'b';
  o.Z:= 3;
  THidingBase(o).X:= 7;
  THidingBase(o).Y:= 8;

  Assert.AreEqual(JSONOK,JSON.Marshal(o,s));
  Assert.AreEqual('{"X":"a","Z":3,"Y":"b"}',s,false);

  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"X":"q","Y":"r","Z":4}',o));
  Assert.AreEqual('q',o.X,false);
  Assert.AreEqual('r',o.Y,false);
  Assert.AreEqual(4,o.Z);
  Assert.AreEqual(7,THidingBase(o).X,'the hidden field is not decoded into');
  Assert.AreEqual(8,THidingBase(o).Y);

  o.Free;
end;

initialization
  TDUnitX.RegisterTestFixture(TObjectsTest);

end.
