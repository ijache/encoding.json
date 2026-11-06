unit TestSuite;

// The JSONTestSuite corpus, one test per file: y_ must be accepted, n_ rejected,
// i_ is accepted unless listed in IMPL_DEFINED_REJECT. A file is validated with
// SkipValue through an ordinary registered parser; y_ files also round-trip through
// a Variant.

interface

uses
  DUnitX.TestFramework,
  encoding.json;

type
  // holds nothing. In the interface on purpose: a type declared under implementation
  // has no qualified name, and the registration would never match
  TAnyJSON = record
  end;

  // turns every file in the corpus-directory into a test-case
  JSONTestSuiteFilesAttribute = class(CustomTestCaseSourceAttribute)
  protected
    function GetCaseInfoArray: TestCaseInfoArray; override;
  end;

  // the same, for the files that must be accepted
  JSONTestSuiteAcceptedFilesAttribute = class(CustomTestCaseSourceAttribute)
  protected
    function GetCaseInfoArray: TestCaseInfoArray; override;
  end;

  [TestFixture]
  TTestSuiteTest = class
  public
    [Test]
    [JSONTestSuiteFiles]
    procedure ConformsToSpec(const filename: string);

    [Test]
    [JSONTestSuiteAcceptedFiles]
    procedure RoundTripsThroughAVariant(const filename: string);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.TypInfo,
  System.IOUtils;

const
  BASEPATH = '..\..\..\testdata\JSONTestSuite\';

  // input encodings this unit does not read; all four fail lexically. Numbers a
  // destination cannot hold are TestSadPaths' business, not the grammar's
  IMPL_DEFINED_REJECT: array[0..3] of string = (
    'i_string_UTF-16LE_with_BOM.json',
    'i_string_utf16BE_no_BOM.json',
    'i_string_utf16LE_no_BOM.json',
    'i_structure_UTF-8_BOM_empty_object.json'
  );

  // 500 levels of nesting is far beyond JSON_DEFAULTMAXDEPTH, so the default
  // configuration rejects it by design
  DEPTH_LIMITED = 'i_structure_500_nested_arrays.json';

  NO_FILES = '';

var
  // an instance of its own: registering on the global JSON would change decoding
  // for every other fixture
  Validator: TJSONCodec = nil;

// the whole point: consume one complete value, validate it, keep nothing
function ParseAnything(j: TJSONCodec; r: PJSONReader; ti: PTypeInfo; data: Pointer): TJSONResult;
begin
  result:= r.SkipValue;
end;

// one case per corpus file matching mask
function CorpusCases(const mask: string): TestCaseInfoArray;
var
  sr: TSearchRec;
  n: integer;
begin
  result:= nil;
  n:= 0;

  if FindFirst(BASEPATH + mask,faAnyFile,sr) = 0 then try
    repeat
      if (sr.Attr and faDirectory) <> 0 then continue;
      if n = Length(result) then SetLength(result,64+n*2);
      result[n].Name:= sr.Name;
      SetLength(result[n].Values,1);
      result[n].Values[0]:= sr.Name;
      inc(n);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;

  // an empty corpus must fail loudly - silently running zero cases is exactly
  // how this suite went unnoticed before
  if n = 0 then begin
    SetLength(result,1);
    result[0].Name:= 'no-testdata-found';
    SetLength(result[0].Values,1);
    result[0].Values[0]:= NO_FILES;
    exit;
  end;

  SetLength(result,n);
end;

function JSONTestSuiteFilesAttribute.GetCaseInfoArray: TestCaseInfoArray;
begin
  result:= CorpusCases('*_*.json');
end;

function JSONTestSuiteAcceptedFilesAttribute.GetCaseInfoArray: TestCaseInfoArray;
begin
  result:= CorpusCases('y_*.json');
end;

{ TTestSuiteTest }

procedure TTestSuiteTest.ConformsToSpec(const filename: string);
var
  contents: TArray<byte>;
  gotValue: TAnyJSON;
  gotResult: TJSONResult;
  wantAccept,gotAccept: boolean;
begin
  if filename = NO_FILES then
    Assert.Fail('no JSONTestSuite files found in ' + ExpandFileName(BASEPATH));

  case filename[1] of
    'y': wantAccept:= true;
    'n': wantAccept:= false;
  else
    // i_: accepted unless explicitly listed
    wantAccept:= not MatchText(filename,IMPL_DEFINED_REJECT) and (filename <> DEPTH_LIMITED);
  end;

  contents:= TFile.ReadAllBytes(BASEPATH + filename);
  gotResult:= Validator.Unmarshal(pointer(contents),Length(contents),gotValue);
  gotAccept:= (gotResult = JSONOK);

  Assert.AreEqual(wantAccept,gotAccept,
    Format('%s -> %s',[filename,GetEnumName(TypeInfo(TJSONResult),Ord(gotResult))]));
end;

// decode, encode, decode, encode: valid in, valid and stable out. Not a check
// that nothing was lost - that is TestVarDict's job
procedure TTestSuiteTest.RoundTripsThroughAVariant(const filename: string);
var
  contents: TArray<byte>;
  v,again: Variant;
  first,second: UTF8String;
  gotResult: TJSONResult;

  function Named(const step: string): string;
  begin
    result:= Format('%s, %s -> %s',[filename,step,GetEnumName(TypeInfo(TJSONResult),Ord(gotResult))]);
  end;

begin
  if filename = NO_FILES then
    Assert.Fail('no JSONTestSuite files found in ' + ExpandFileName(BASEPATH));

  contents:= TFile.ReadAllBytes(BASEPATH + filename);
  gotResult:= JSON.Unmarshal(pointer(contents),Length(contents),v);
  Assert.AreEqual(JSONOK,gotResult,Named('decode'));
  gotResult:= JSON.Marshal(v,first);
  Assert.AreEqual(JSONOK,gotResult,Named('encode'));
  gotResult:= JSON.Unmarshal(first,again);
  Assert.AreEqual(JSONOK,gotResult,Named('decode what was encoded'));
  gotResult:= JSON.Marshal(again,second);
  Assert.AreEqual(JSONOK,gotResult,Named('encode again'));
  Assert.AreEqual(string(first),string(second),filename+', the second encode differs');
end;

initialization
  Validator:= TJSONCodec.Create(JSONDefaultConfig);
  Validator.RegisterParser<TAnyJSON>(@ParseAnything);

  TDUnitX.RegisterTestFixture(TTestSuiteTest);

finalization
  Validator.Free;

end.
