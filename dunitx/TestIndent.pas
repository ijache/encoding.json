unit TestIndent;

interface

uses
  DUnitX.TestFramework,
  encoding.json;

type
  [TestFixture]
  TIndentTest = class
  public
    [Test] procedure TestIndent;
  end;

implementation

{ TIndentTest }

type
  TBasicRecord = record
    StringField: string;
    IntField: integer;
    FloatField: double;
    BoolField: boolean;
    SomeArray: array of integer;
  end;

  TNothing = record
  end;

  TWithEmpties = record
    Before: integer;
    Items: TArray<integer>;
    Inner: TNothing;
    After: integer;
  end;


procedure TIndentTest.TestIndent;
var
  gotResult: TJSONResult;
  gotJSON: string;
  someRecord: TBasicRecord;
  expected: string;
begin
  someRecord.StringField:= 'a string';
  someRecord.IntField:= 42;
  someRecord.FloatField:= 3.14159;
  someRecord.BoolField:= true;
  someRecord.SomeArray:= [1,2,3,4];

  gotResult:= JSON.MarshalIndent(someRecord,'  ',gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  expected:=
'{'#10+
'  "StringField": "a string",'#10+
'  "IntField": 42,'#10+
'  "FloatField": 3.14159,'#10+
'  "BoolField": true,'#10+
'  "SomeArray": ['#10+
'    1,'#10+
'    2,'#10+
'    3,'#10+
'    4'#10+
'  ]'#10+
'}';
  Assert.AreEqual(expected,gotJSON);

  // an empty aggregate closes on the line it opened on, as in Go
  var empties: TWithEmpties;
  empties.Before:= 1;
  empties.Items:= nil;
  empties.After:= 2;

  gotResult:= JSON.MarshalIndent(empties,'  ',gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  expected:=
'{'#10+
'  "Before": 1,'#10+
'  "Items": [],'#10+
'  "Inner": {},'#10+
'  "After": 2'#10+
'}';
  Assert.AreEqual(expected,gotJSON,'empty containers between members');

  gotResult:= JSON.MarshalIndent(empties.Items,'  ',gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('[]',gotJSON,'an empty array on its own');
end;

initialization
  TDUnitX.RegisterTestFixture(TIndentTest);

end.
