unit TestErrorInfo;

// TJSONErrorInfo. The offset is where the failing token started, not where the
// reader gave up - pinned exactly, or "somewhere near" becomes the contract.

interface

uses
  DUnitX.TestFramework;

type
  TColour = (clRed, clGreen);

  TPlain = record
    Alpha: integer;
    Beta: string;
  end;

  TNested = record
    Name: string;
    Inner: TPlain;
  end;

  // no formatter for a method pointer: wrapped in an array, so FormatArray reports
  // it - a bare member would just be skipped
  TProc = procedure of object;
  TProcs = array of TProc;
  TUnencodable = record
    Good: integer;
    Bad: TProcs;
  end;

  // a member with no type info at all is refused too, and has no type to report
  TUntypedMember = record
    Untyped: array[0..1] of integer;
  end;
  TUntypedInside = record
    Good: integer;
    Inner: TUntypedMember;
  end;

  [TestFixture]
  TErrorInfoTest = class
  public
    [Test] procedure TestSuccessLeavesInfoClean;
    [Test] procedure TestOffsetPointsAtOffendingToken;
    [Test] procedure TestOffsetAtVeryFirstByte;
    [Test] procedure TestTrailingGarbageOffset;
    [Test] procedure TestDepthIsFailureDepth;
    [Test] procedure TestMaxDepthReports;
    [Test] procedure TestNilInfoIsAccepted;
    [Test] procedure TestFormatNamesTheFailingMember;
    [Test] procedure TestFormatReportsUnsupportedTopLevelType;
    [Test] procedure TestInfoIsResetBetweenCalls;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  encoding.json;

procedure TErrorInfoTest.TestSuccessLeavesInfoClean;
var
  info: TJSONErrorInfo;
  got: TPlain;
  s: UTF8String;
begin
  info.Offset:= 999; info.Depth:= 999;   // must be cleared, not left alone
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"Alpha":1,"Beta":"b"}'),got,@info));
  Assert.AreEqual(JSONOK,info.Code,'code');
  Assert.AreEqual(0,info.Offset,'offset');
  Assert.AreEqual(0,info.Depth,'depth');
  Assert.AreEqual('',info.MemberName,'member');

  Assert.AreEqual(JSONOK,JSON.Marshal(got,s,@info));
  Assert.AreEqual(JSONOK,info.Code,'code after marshal');
  Assert.AreEqual('',info.MemberName,'member after marshal');
end;

// the value for Alpha is bad. it starts at index 10, counting the opening
// brace as 0:  {"Alpha":  is 9 characters, so the 'x' sits at 10.
procedure TErrorInfoTest.TestOffsetPointsAtOffendingToken;
var
  info: TJSONErrorInfo;
  got: TPlain;
  src: UTF8String;
begin
  src:= '{"Alpha":xyz}';
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(src,got,@info));
  Assert.AreEqual(JSONSyntax,info.Code,'code');
  Assert.AreEqual(9,info.Offset,'offset should point at the x, not past it');
  Assert.AreEqual(AnsiChar('x'),AnsiChar(src[info.Offset+1]),'byte at offset');
end;

procedure TErrorInfoTest.TestOffsetAtVeryFirstByte;
var
  info: TJSONErrorInfo;
  got: TPlain;
begin
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(UTF8String('!'),got,@info));
  Assert.AreEqual(0,info.Offset,'a bad first byte is offset 0');
end;

// leading whitespace must not count against the token position
procedure TErrorInfoTest.TestTrailingGarbageOffset;
var
  info: TJSONErrorInfo;
  got: TPlain;
  src: UTF8String;
begin
  src:= '{"Alpha":1}   @@@';
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(src,got,@info));
  Assert.AreEqual(14,info.Offset,'offset should skip the whitespace and land on the @');
  Assert.AreEqual(AnsiChar('@'),AnsiChar(src[info.Offset+1]),'byte at offset');
end;

// the failure is inside Inner, one level below the outer object, so the depth
// reported has to be the depth at the failure - not 0, and not the top level
procedure TErrorInfoTest.TestDepthIsFailureDepth;
var
  info: TJSONErrorInfo;
  shallow,deep: TJSONErrorInfo;
  gotN: TNested;
  gotP: TPlain;
begin
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(UTF8String('{"Alpha":@}'),gotP,@shallow));
  Assert.AreEqual(JSONSyntax,
    JSON.Unmarshal(UTF8String('{"Name":"n","Inner":{"Alpha":@}}'),gotN,@deep));

  Assert.IsTrue(deep.Depth > shallow.Depth,
    Format('nested failure should report a deeper level (outer=%d, nested=%d)',
      [shallow.Depth,deep.Depth]));

  info:= deep;
  Assert.AreEqual(2,info.Depth,'one object inside another is depth 2');
end;

// an unknown key is consumed by SkipValue, which recurses and honours
// MaxDepth - so this reaches the limit without needing a 100-deep delphi type
procedure TErrorInfoTest.TestMaxDepthReports;
var
  info: TJSONErrorInfo;
  got: TPlain;
  src: UTF8String;
  i: integer;
begin
  src:= '{"unknown":';
  for i:= 1 to 100 do src:= src + '[';
  for i:= 1 to 100 do src:= src + ']';
  src:= src + '}';

  Assert.AreEqual(JSONMaxDepthReached,JSON.Unmarshal(src,got,@info));
  Assert.AreEqual(JSONMaxDepthReached,info.Code,'code');
  Assert.IsTrue(info.Depth > 1,
    Format('depth should show how deep it got, was %d',[info.Depth]));
  Assert.IsTrue(info.Offset > 0,'offset should point into the nesting');
end;

// the whole point of the pointer-with-default: existing callers pass nothing,
// and asking for detail must not change the result they get
procedure TErrorInfoTest.TestNilInfoIsAccepted;
var
  info: TJSONErrorInfo;
  got: TPlain;
  withInfo,without: TJSONResult;
  s: UTF8String;
begin
  without := JSON.Unmarshal(UTF8String('{'),got);
  withInfo:= JSON.Unmarshal(UTF8String('{'),got,@info);
  Assert.AreNotEqual(JSONOK,without,'precondition: this input fails');
  Assert.AreEqual(without,withInfo,'result must not depend on asking for detail');
  Assert.AreEqual(without,info.Code,'info.Code must agree with the result');

  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"Alpha":1}'),got,nil));
  Assert.AreEqual(JSONOK,JSON.Marshal(got,s));
end;

procedure TErrorInfoTest.TestFormatNamesTheFailingMember;
var
  info: TJSONErrorInfo;
  bad: TUnencodable;
  s: UTF8String;
begin
  bad.Good:= 1;
  SetLength(bad.Bad,1);
  bad.Bad[0]:= nil;

  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(bad,s,@info));
  Assert.AreEqual(JSONUnsupportedType,info.Code,'code');
  Assert.AreEqual('Bad',info.MemberName,'the member that could not be encoded');
  Assert.IsTrue(info.FailedType <> nil,'failing type should be reported');

  var untyped:= Default(TUntypedInside);
  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(untyped,s,@info));
  Assert.AreEqual('Untyped',info.MemberName,'the innermost member, though it has no type');
  Assert.IsTrue(info.FailedType = nil,'...and so no type to report');
end;

// nothing names a member when the top-level value itself has no formatter -
// the type still has to come back
procedure TErrorInfoTest.TestFormatReportsUnsupportedTopLevelType;
var
  info: TJSONErrorInfo;
  procs: TProcs;
  s: UTF8String;
begin
  SetLength(procs,1);
  procs[0]:= nil;

  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(procs,s,@info));
  Assert.AreEqual(JSONUnsupportedType,info.Code,'code');
  Assert.AreEqual('',info.MemberName,'no member is involved');
  Assert.IsTrue(info.FailedType = System.TypeInfo(TProcs),'the top-level type');
end;

// a record filled by a failing call must not keep stale detail after a
// subsequent successful one, or callers will report the wrong thing
procedure TErrorInfoTest.TestInfoIsResetBetweenCalls;
var
  info: TJSONErrorInfo;
  got: TPlain;
begin
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(UTF8String('{"Alpha":@}'),got,@info));
  Assert.IsTrue(info.Offset > 0,'precondition: first call recorded an offset');

  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('{"Alpha":1,"Beta":"b"}'),got,@info));
  Assert.AreEqual(JSONOK,info.Code,'code');
  Assert.AreEqual(0,info.Offset,'offset must be cleared');
  Assert.AreEqual(0,info.Depth,'depth must be cleared');
end;

initialization
  TDUnitX.RegisterTestFixture(TErrorInfoTest);

end.
