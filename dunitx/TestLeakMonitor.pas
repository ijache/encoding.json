unit TestLeakMonitor;

// Makes DUnitX's per-test leak check real: without a registered monitor it
// measures nothing. Counts bytes in use around each test, which includes what a
// test allocates for good on first use - so Tests.dpr runs a silent pass first.

interface

// from here on, every test is checked for leaks
procedure CountLeaks;

implementation

uses
  DUnitX.TestFramework,
  DUnitX.IoC;

type
  TLeakMonitor = class(TInterfacedObject,IMemoryLeakMonitor)
  private
    fPreSetup,fPostSetup: Int64;
    fPreTest,fPostTest: Int64;
    fPreTearDown,fPostTearDown: Int64;
  public
    procedure PreSetup;
    procedure PostSetUp;
    procedure PreTest;
    procedure PostTest;
    procedure PreTearDown;
    procedure PostTearDown;
    function SetUpMemoryAllocated: Int64;
    function TearDownMemoryAllocated: Int64;
    function TestMemoryAllocated: Int64;
  end;

function BytesInUse: Int64;
var
  ms: TMemoryManagerState;
  sb: TSmallBlockTypeState;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  GetMemoryManagerState(ms);
  {$WARN SYMBOL_PLATFORM ON}
  result:= ms.TotalAllocatedMediumBlockSize + ms.TotalAllocatedLargeBlockSize;
  for sb in ms.SmallBlockTypeStates do
    result:= result + Int64(sb.UseableBlockSize) * Int64(sb.AllocatedBlockCount);
end;

procedure TLeakMonitor.PreSetup;     begin fPreSetup:= BytesInUse; end;
procedure TLeakMonitor.PostSetUp;    begin fPostSetup:= BytesInUse; end;
procedure TLeakMonitor.PreTest;      begin fPreTest:= BytesInUse; end;
procedure TLeakMonitor.PostTest;     begin fPostTest:= BytesInUse; end;
procedure TLeakMonitor.PreTearDown;  begin fPreTearDown:= BytesInUse; end;
procedure TLeakMonitor.PostTearDown; begin fPostTearDown:= BytesInUse; end;

function TLeakMonitor.SetUpMemoryAllocated: Int64;
begin
  result:= fPostSetup - fPreSetup;
end;

function TLeakMonitor.TearDownMemoryAllocated: Int64;
begin
  result:= fPostTearDown - fPreTearDown;
end;

function TLeakMonitor.TestMemoryAllocated: Int64;
begin
  result:= fPostTest - fPreTest;
end;

// replaces DUnitX's do-nothing default. the runner resolves the monitor
// afresh for every fixture, so this takes effect at the next one
procedure CountLeaks;
begin
  TDUnitXIoC.DefaultContainer.RegisterType<IMemoryLeakMonitor>(
    function: IMemoryLeakMonitor
    begin
      result:= TLeakMonitor.Create;
    end);
end;

end.
