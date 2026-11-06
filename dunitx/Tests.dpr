program Tests;

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}
uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  {$ENDIF }
  DUnitX.TestFramework,
  TestLeakMonitor in 'TestLeakMonitor.pas',
  TestHelpers in 'TestHelpers.pas',
  encoding.json in '..\source\encoding.json.pas',
  TestObjects in 'TestObjects.pas' ,
  TestSpecialTypes in 'TestSpecialTypes.pas',
  TestArrays in 'TestArrays.pas',
  TestGenericCollections in 'TestGenericCollections.pas',
  TestIndent in 'TestIndent.pas',
  TestRecords in 'TestRecords.pas',
  TestSimpleTypes in 'TestSimpleTypes.pas',
  TestStrings in 'TestStrings.pas',
  TestVariants in 'TestVariants.pas',
  TestAttributes in 'TestAttributes.pas',
  TestCharacterEncoding in 'TestCharacterEncoding.pas',
  TestSuite in 'TestSuite.pas',
  TestScalarTypes in 'TestScalarTypes.pas',
  TestTypeCache in 'TestTypeCache.pas',
  TestErrorInfo in 'TestErrorInfo.pas',
  TestConfig in 'TestConfig.pas',
  TestRegister in 'TestRegister.pas',
  TestSadPaths in 'TestSadPaths.pas',
  TestSets in 'TestSets.pas',
  TestGotchas in 'TestGotchas.pas',
  TestSortKeys in 'TestSortKeys.pas',
  TestVarDict in 'TestVarDict.pas',
  TestConcurrency in 'TestConcurrency.pas',
  TestJSONBench in 'TestJSONBench.pas';

{$IFNDEF TESTINSIGHT}
var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger : ITestLogger;
{$ENDIF}
begin
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
{$ELSE}
  try
    //Check command line options, will exit if invalid
    TDUnitX.CheckCommandLine;
    //Create the test runner
    runner := TDUnitX.CreateRunner;
    //Tell the runner to use RTTI to find Fixtures
    runner.UseRTTI := True;
    //When true, Assertions must be made during tests;
    runner.FailsOnNoAsserts := False;
    TDUnitX.Options.ExitBehavior:= TDUnitXExitBehavior.Pause;
    // DUnitX compares strings case-insensitively by default, hiding every casing
    // regression
    Assert.IgnoreCaseDefault:= false;

    // a silent first pass allocates what tests keep for good (RTTI, caches), so the
    // counted pass reports only real leaks. Same runner: DUnitX allows one per thread
    runner.Execute;
    CountLeaks;

    //tell the runner how we will log things
    //Log to the console window if desired
    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      logger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      runner.AddLogger(logger);
    end;
    //Generate an NUnit compatible XML File
    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);

    //Run tests
    results := runner.Execute;
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    {$IFNDEF CI}
    //We don't want this happening when running under CI.
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
{$ENDIF}
end.
