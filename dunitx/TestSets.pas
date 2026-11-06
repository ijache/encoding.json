unit TestSets;

interface

uses
  DUnitX.TestFramework,
  SysUtils,
  encoding.json;

type
  TStyle = (fsBold, fsItalic, fsUnderline);
  TStyles = set of TStyle;
  PStyles = ^TStyles;

  // 100 members, 13 bytes - keep it wider than 8. Bits above 31 need a set that has
  // them, and below 9 bytes the allocator's slack hides a wrong TypeSize: an 8-byte
  // set passed with TypeSize broken. See TestPointerToLargeSet.
  TWide = (v00,v01,v02,v03,v04,v05,v06,v07,v08,v09,
           v10,v11,v12,v13,v14,v15,v16,v17,v18,v19,
           v20,v21,v22,v23,v24,v25,v26,v27,v28,v29,
           v30,v31,v32,v33,v34,v35,v36,v37,v38,v39,
           v40,v41,v42,v43,v44,v45,v46,v47,v48,v49,
           v50,v51,v52,v53,v54,v55,v56,v57,v58,v59,
           v60,v61,v62,v63,v64,v65,v66,v67,v68,v69,
           v70,v71,v72,v73,v74,v75,v76,v77,v78,v79,
           v80,v81,v82,v83,v84,v85,v86,v87,v88,v89,
           v90,v91,v92,v93,v94,v95,v96,v97,v98,v99);
  TWideSet = set of TWide;
  PWideSet = ^TWideSet;

  TStyleRec = record
    Name: string;
    Styles: TStyles;
  end;

  TWideRec = record
    Wide: TWideSet;
  end;

  TOmitRec = record
    [JSON('styles',true)] Styles: TStyles;
    [JSON('name')] Name: string;
  end;

  TPointerRec = record
    Styles: PStyles;
  end;

  // an array of them, because one wrong-sized block on its own overwrites
  // only slack. a hundred in a row overwrite each other.
  TWidePointerRec = record
    Sets: array of PWideSet;
  end;

  [TestFixture]
  TSetsTest = class
  private
    // encodes a record carrying just the set, and asserts the array it wrote
    procedure AssertEncodes(const someStyles: TStyles; const wantJSON: string; const because: string);
    // decodes into a record whose set starts out holding fsItalic, so every
    // case also proves the destination is replaced rather than merged into
    function DecodeStyles(const someJSON: string; out gotStyles: TStyles): TJSONResult;
    procedure AssertDecodes(const someJSON: string; const wantStyles: TStyles; const because: string);
    procedure AssertRejects(const someJSON: string; wantResult: TJSONResult; const because: string);
  public
    [Test] procedure TestEncodeEmptySet;
    [Test] procedure TestEncodeMembers;
    [Test] procedure TestEncodeUsesDeclarationOrder;
    [Test] procedure TestDecodeEmptyArray;
    [Test] procedure TestDecodeNull;
    [Test] procedure TestDecodeMembers;
    [Test] procedure TestDecodeToleratesDuplicates;
    [Test] procedure TestDecodeIgnoresOrder;
    [Test] procedure TestDecodeReplacesDestination;
    [Test] procedure TestRejectsUnknownMemberName;
    [Test] procedure TestRejectsNonStringElements;
    [Test] procedure TestRejectsWrongShape;
    [Test] procedure TestRejectedShapeEmptiesTheSet;
    [Test] procedure TestRejectsBrokenDocument;
    [Test] procedure TestLargeSetRoundTrip;
    [Test] procedure TestPointerToSet;
    [Test] procedure TestPointerToLargeSet;
    [Test] procedure TestOmitEmpty;
    [Test] procedure TestTopLevelSet;
  end;

implementation

{ TSetsTest }

procedure TSetsTest.AssertEncodes(const someStyles: TStyles; const wantJSON: string; const because: string);
var
  someRec: TStyleRec;
  gotResult: TJSONResult;
  gotJSON: string;
begin
  someRec.Name:= 'n';
  someRec.Styles:= someStyles;

  gotResult:= JSON.Marshal(someRec,gotJSON);
  Assert.AreEqual(JSONOK,gotResult,because);
  Assert.AreEqual('{"Name":"n","Styles":'+wantJSON+'}',gotJSON,because);
end;

function TSetsTest.DecodeStyles(const someJSON: string; out gotStyles: TStyles): TJSONResult;
var
  someRec: TStyleRec;
begin
  // deliberately non-empty going in: a parser that only ever adds bits would
  // pass every case below if the destination started out empty
  someRec.Name:= '';
  someRec.Styles:= [fsItalic];

  result:= JSON.Unmarshal(someJSON,someRec);
  gotStyles:= someRec.Styles;
end;

procedure TSetsTest.AssertDecodes(const someJSON: string; const wantStyles: TStyles; const because: string);
var
  gotResult: TJSONResult;
  gotStyles: TStyles;
begin
  gotResult:= DecodeStyles(someJSON,gotStyles);
  Assert.AreEqual(JSONOK,gotResult,because);
  Assert.IsTrue(gotStyles = wantStyles,because);
end;

procedure TSetsTest.AssertRejects(const someJSON: string; wantResult: TJSONResult; const because: string);
var
  gotResult: TJSONResult;
  gotStyles: TStyles;
begin
  try
    gotResult:= DecodeStyles(someJSON,gotStyles);
  except
    // an escaping exception is a contract break, so it fails as a named
    // assertion here rather than as a DUnitX "Errored"
    on e: Exception do begin
      Assert.Fail(because+' - raised '+e.ClassName+': '+e.Message);
      exit;
    end;
  end;
  Assert.AreEqual(wantResult,gotResult,because);
end;

//----------------------------------------------------------------------------
// encode
//----------------------------------------------------------------------------

procedure TSetsTest.TestEncodeEmptySet;
begin
  AssertEncodes([],'[]','the empty set is the empty array');
end;

procedure TSetsTest.TestEncodeMembers;
begin
  AssertEncodes([fsBold],'["fsBold"]','one member');
  AssertEncodes([fsBold,fsUnderline],'["fsBold","fsUnderline"]','two members');
  AssertEncodes([fsBold,fsItalic,fsUnderline],
    '["fsBold","fsItalic","fsUnderline"]','every member');
end;

// a set does not remember an order, so the one that comes out is the
// enumeration's. asserting it pins the output down as reproducible.
procedure TSetsTest.TestEncodeUsesDeclarationOrder;
begin
  AssertEncodes([fsUnderline,fsBold],'["fsBold","fsUnderline"]',
    'declaration order, not the order the members were written');
end;

//----------------------------------------------------------------------------
// decode
//----------------------------------------------------------------------------

procedure TSetsTest.TestDecodeEmptyArray;
begin
  AssertDecodes('{"Styles":[]}',[],'an empty array is the empty set');
end;

// null and [] are the same empty set: a producer that omits a set by writing
// null must not need a different destination type than one writing []
procedure TSetsTest.TestDecodeNull;
begin
  AssertDecodes('{"Styles":null}',[],'null is the empty set');
end;

procedure TSetsTest.TestDecodeMembers;
begin
  AssertDecodes('{"Styles":["fsBold"]}',[fsBold],'one member');
  AssertDecodes('{"Styles":["fsBold","fsUnderline"]}',[fsBold,fsUnderline],'two members');
end;

// deliberately tolerant: a set has no multiplicity to violate, so a repeated
// name sets a bit that is already set
procedure TSetsTest.TestDecodeToleratesDuplicates;
begin
  AssertDecodes('{"Styles":["fsBold","fsBold","fsBold"]}',[fsBold],
    'a repeated member is not an error');
end;

procedure TSetsTest.TestDecodeIgnoresOrder;
begin
  AssertDecodes('{"Styles":["fsUnderline","fsBold"]}',[fsBold,fsUnderline],
    'the document order does not matter');
end;

// the destination DecodeStyles hands in holds fsItalic. every case above
// relies on this, but only this one says so.
procedure TSetsTest.TestDecodeReplacesDestination;
begin
  AssertDecodes('{"Styles":["fsBold"]}',[fsBold],
    'decoding replaces the set rather than merging into it');
  AssertDecodes('{"Styles":[]}',[],
    'an empty array clears what the destination held');
end;

//----------------------------------------------------------------------------
// sad paths - exact codes on purpose
//----------------------------------------------------------------------------

procedure TSetsTest.TestRejectsUnknownMemberName;
begin
  AssertRejects('{"Styles":["fsNope"]}',JSONTypeMismatch,
    'a name the enumeration does not have');
  AssertRejects('{"Styles":["fsBold","fsNope"]}',JSONTypeMismatch,
    '...also when it is not the first element');
end;

procedure TSetsTest.TestRejectsNonStringElements;
begin
  AssertRejects('{"Styles":[1]}',JSONTypeMismatch,'a number names no member');
  AssertRejects('{"Styles":[true]}',JSONTypeMismatch,'nor does a literal');
  AssertRejects('{"Styles":[null]}',JSONTypeMismatch,'nor does null in element position');
  AssertRejects('{"Styles":[["fsBold"]]}',JSONTypeMismatch,'nor does a nested array');
end;

procedure TSetsTest.TestRejectsWrongShape;
begin
  AssertRejects('{"Styles":"fsBold"}',JSONTypeMismatch,'a bare string is not an array');
  AssertRejects('{"Styles":{"fsBold":true}}',JSONTypeMismatch,'nor is an object');
  AssertRejects('{"Styles":1}',JSONTypeMismatch,'nor is a number');
end;

// emptied before the shape is known, so a refused document leaves it empty - as
// for every other aggregate
procedure TSetsTest.TestRejectedShapeEmptiesTheSet;
var
  gotResult: TJSONResult;
  gotStyles: TStyles;
begin
  gotResult:= DecodeStyles('{"Styles":1}',gotStyles);
  Assert.AreEqual(JSONTypeMismatch,gotResult,'a number is not an array');
  Assert.IsTrue(gotStyles = [],'the set is emptied anyway');

  gotResult:= DecodeStyles('{"Styles":{"fsBold":true}}',gotStyles);
  Assert.AreEqual(JSONTypeMismatch,gotResult,'nor is an object');
  Assert.IsTrue(gotStyles = [],'...and that empties it too');
end;

// a broken document, as opposed to a well-formed one aimed at the wrong type
procedure TSetsTest.TestRejectsBrokenDocument;
begin
  AssertRejects('{"Styles":["fsBold"}',JSONSyntax,'the array is never closed');
  AssertRejects('{"Styles":["fsBold",}',JSONSyntax,'a comma with nothing after it');
end;

//----------------------------------------------------------------------------
// widths and indirection
//----------------------------------------------------------------------------

// the bit arithmetic, on a set with bits well above the 32 an integer holds
procedure TSetsTest.TestLargeSetRoundTrip;
var
  someRec: TWideRec;
  gotRec: TWideRec;
  gotResult: TJSONResult;
  gotJSON: string;
begin
  someRec.Wide:= [v00,v08,v31,v32,v39,v99];

  gotResult:= JSON.Marshal(someRec,gotJSON);
  Assert.AreEqual(JSONOK,gotResult,'encoding a set wider than four bytes');
  Assert.AreEqual('{"Wide":["v00","v08","v31","v32","v39","v99"]}',gotJSON,
    'every member survives, including the ones above bit 31');

  gotRec.Wide:= [];
  gotResult:= JSON.Unmarshal(gotJSON,gotRec);
  Assert.AreEqual(JSONOK,gotResult,'decoding it back');
  Assert.IsTrue(gotRec.Wide = someRec.Wide,'the set round-trips');
end;

// ParsePointer allocates by TypeSize, so a pointer to a set is the path that
// turns a wrong size into a wrong-sized heap block rather than a wrong answer
procedure TSetsTest.TestPointerToSet;
var
  someRec: TPointerRec;
  gotResult: TJSONResult;
begin
  someRec.Styles:= nil;

  gotResult:= JSON.Unmarshal('{"Styles":["fsBold","fsUnderline"]}',someRec);
  try
    Assert.AreEqual(JSONOK,gotResult,'decoding through a pointer to a set');
    Assert.IsTrue(someRec.Styles <> nil,'the pointer was allocated');
    Assert.IsTrue(someRec.Styles^ = [fsBold,fsUnderline],'and filled');
  finally
    if someRec.Styles <> nil then FreeMem(someRec.Styles);
  end;
end;

// a hundred of them: each write runs off its own block into the next, while a
// single one only overwrites slack and looks correct
procedure TSetsTest.TestPointerToLargeSet;
var
  someRec: TWidePointerRec;
  gotResult: TJSONResult;
  someJSON: string;
  i: integer;
  wrong: integer;
begin
  someJSON:= '{"Sets":[';
  for i:= 0 to 99 do begin
    if i > 0 then someJSON:= someJSON + ',';
    someJSON:= someJSON + '["v00","v99"]';
  end;
  someJSON:= someJSON + ']}';

  gotResult:= JSON.Unmarshal(someJSON,someRec);
  try
    Assert.AreEqual(JSONOK,gotResult,'decoding a hundred pointers to a wide set');
    Assert.AreEqual(100,integer(Length(someRec.Sets)),'all hundred arrived');

    wrong:= 0;
    for i:= 0 to High(someRec.Sets) do
      if someRec.Sets[i]^ <> [v00,v99] then inc(wrong);

    Assert.AreEqual(0,wrong,'no element was overwritten by its neighbour');
  finally
    for i:= 0 to High(someRec.Sets) do
      if someRec.Sets[i] <> nil then FreeMem(someRec.Sets[i]);
  end;
end;

procedure TSetsTest.TestOmitEmpty;
var
  someRec: TOmitRec;
  gotResult: TJSONResult;
  gotJSON: string;
begin
  someRec.Name:= 'x';
  someRec.Styles:= [];

  gotResult:= JSON.Marshal(someRec,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('{"name":"x"}',gotJSON,'an empty set is omitted like an empty array');

  someRec.Styles:= [fsBold];
  gotResult:= JSON.Marshal(someRec,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('{"styles":["fsBold"],"name":"x"}',gotJSON,'a non-empty one is written');
end;

// nothing about a set requires it to be a member of anything
procedure TSetsTest.TestTopLevelSet;
var
  someStyles: TStyles;
  gotStyles: TStyles;
  gotResult: TJSONResult;
  gotJSON: string;
begin
  someStyles:= [fsItalic,fsUnderline];

  gotResult:= JSON.Marshal(someStyles,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('["fsItalic","fsUnderline"]',gotJSON);

  gotStyles:= [];
  gotResult:= JSON.Unmarshal(gotJSON,gotStyles);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.IsTrue(gotStyles = someStyles,'a top-level set round-trips');
end;

initialization
  TDUnitX.RegisterTestFixture(TSetsTest);

end.
