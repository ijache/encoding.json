unit TestJSONBench;

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.SysUtils,
  System.IOUtils,
  System.Rtti,
  System.Classes,
  System.StrUtils,
  Variants,
  encoding.json;

type
  [TestFixture]
  TTestJSONBench = class
  public
    [Test] procedure TestUnicode();
  end;

implementation


type UnicodeStrings = record
[JSON('Arabic')] Arabic: string;
[JSON('Arabic Presentation Forms-A')] Arabic_Presentation_Forms_A: string;
[JSON('Arabic Presentation Forms-B')] Arabic_Presentation_Forms_B: string;
[JSON('Armenian')] Armenian: string;
[JSON('Arrows')] Arrows: string;
[JSON('Bengali')] Bengali: string;
[JSON('Bopomofo')] Bopomofo: string;
[JSON('Box Drawing')] Box_Drawing: string;
[JSON('CJK Compatibility')] CJK_Compatibility: string;
[JSON('CJK Compatibility Forms')] CJK_Compatibility_Forms: string;
[JSON('CJK Compatibility Ideographs')] CJK_Compatibility_Ideographs: string;
[JSON('CJK Symbols and Punctuation')] CJK_Symbols_and_Punctuation: string;
[JSON('CJK Unified Ideographs')] CJK_Unified_Ideographs: string;
[JSON('CJK Unified Ideographs Extension A')] CJK_Unified_Ideographs_Extension_A: string;
[JSON('CJK Unified Ideographs Extension B')] CJK_Unified_Ideographs_Extension_B: string;
[JSON('Cherokee')] Cherokee: string;
[JSON('Currency Symbols')] Currency_Symbols: string;
[JSON('Cyrillic')] Cyrillic: string;
[JSON('Cyrillic Supplementary')] Cyrillic_Supplementary: string;
[JSON('Devanagari')] Devanagari: string;
[JSON('Enclosed Alphanumerics')] Enclosed_Alphanumerics: string;
[JSON('Enclosed CJK Letters and Months')] Enclosed_CJK_Letters_and_Months: string;
[JSON('Ethiopic')] Ethiopic: string;
[JSON('Geometric Shapes')] Geometric_Shapes: string;
[JSON('Georgian')] Georgian: string;
[JSON('Greek and Coptic')] Greek_and_Coptic: string;
[JSON('Gujarati')] Gujarati: string;
[JSON('Gurmukhi')] Gurmukhi: string;
[JSON('Hangul Compatibility Jamo')] Hangul_Compatibility_Jamo: string;
[JSON('Hangul Jamo')] Hangul_Jamo: string;
[JSON('Hangul Syllables')] Hangul_Syllables: string;
[JSON('Hebrew')] Hebrew: string;
[JSON('Hiragana')] Hiragana: string;
[JSON('IPA Extentions')] IPA_Extentions: string;
[JSON('Kangxi Radicals')] Kangxi_Radicals: string;
[JSON('Katakana')] Katakana: string;
[JSON('Khmer')] Khmer: string;
[JSON('Khmer Symbols')] Khmer_Symbols: string;
[JSON('Latin')] Latin: string;
[JSON('Latin Extended Additional')] Latin_Extended_Additional: string;
[JSON('Latin-1 Supplement')] Latin_1_Supplement: string;
[JSON('Latin-Extended A')] Latin_Extended_A: string;
[JSON('Latin-Extended B')] Latin_Extended_B: string;
[JSON('Letterlike Symbols')] Letterlike_Symbols: string;
[JSON('Malayalam')] Malayalam: string;
[JSON('Mathematical Alphanumeric Symbols')] Mathematical_Alphanumeric_Symbols: string;
[JSON('Mathematical Operators')] Mathematical_Operators: string;
[JSON('Miscellaneous Symbols')] Miscellaneous_Symbols: string;
[JSON('Mongolian')] Mongolian: string;
[JSON('Number Forms')] Number_Forms: string;
[JSON('Oriya')] Oriya: string;
[JSON('Phonetic Extensions')] Phonetic_Extensions: string;
[JSON('Supplemental Arrows-B')] Supplemental_Arrows_B: string;
[JSON('Syriac')] Syriac: string;
[JSON('Tamil')] Tamil: string;
[JSON('Thaana')] Thaana: string;
[JSON('Thai')] Thai: string;
[JSON('Unified Canadian Aboriginal Syllabics')] Unified_Canadian_Aboriginal_Syllabics: string;
[JSON('Yi Radicals')] Yi_Radicals: string;
[JSON('Yi Syllables')] Yi_Syllables: string;
end;

function RemoveWhiteSpace(v: UTF8String): UTF8String;
var
  s: string;
begin
  s:= AnsiReplaceStr(string(v),#9,'');
  s:= AnsiReplaceStr(s,#10,'');
  s:= AnsiReplaceStr(s,#13,'');
  s:= AnsiReplaceStr(s,#32,'');
  result:= UTF8String(s);
end;

procedure TTestJSONBench.TestUnicode;
var
  testData: TArray<byte>;
  gotData: UnicodeStrings;
  gotResult: TJSONResult;
  gotJSON: UTF8String;

  compareGot,compareWant: UTF8String;
begin
  testData:= System.IOUtils.TFile.ReadAllBytes('..\..\..\testdata\JSONBench\string_unicode.json');

  gotResult:= JSON.Unmarshal(pointer(testData),length(testData),gotData);
  assert.AreEqual(JSONOK,gotResult);

  gotResult:= JSON.MarshalIndent(gotData,'  ',gotJSON);
  assert.AreEqual(JSONOK,gotResult);

  // contents should be equal. since spacing/indentation might differ
  // we need to adjust both strings
  SetString(compareWant,pansichar(@testdata[0]),Length(testData));
  compareWant:= RemoveWhiteSpace(compareWant);
  compareGot:= RemoveWhiteSpace(gotJSON);
  assert.AreEqual(compareWant,compareGot);

end;

end.
