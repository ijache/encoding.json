unit TestTypeCache;

// The type cache: growing past its capacity, and a cold cache hit from
// several threads. The records have distinctly named fields on purpose: a
// cross-wired entry would still round-trip identically shaped records.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeCacheTest = class
  public
    [Test] procedure TestCacheGrowsPastInitialCapacity;
    [Test] procedure TestConcurrentAccessToColdCache;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.TypInfo,
  encoding.json;

const
  WORKERS  = 8;   // threads released simultaneously onto one cold cache
  ATTEMPTS = 10;  // fresh cache per attempt - the race is only open while cold
  ROUNDS   = 25;  // passes over all 20 types per worker
  WORKER_TIMEOUT = 30000;

type
  TCacheRec01 = record F01: integer; N01: string; end;
  TCacheRec02 = record F02: integer; N02: string; end;
  TCacheRec03 = record F03: integer; N03: string; end;
  TCacheRec04 = record F04: integer; N04: string; end;
  TCacheRec05 = record F05: integer; N05: string; end;
  TCacheRec06 = record F06: integer; N06: string; end;
  TCacheRec07 = record F07: integer; N07: string; end;
  TCacheRec08 = record F08: integer; N08: string; end;
  TCacheRec09 = record F09: integer; N09: string; end;
  TCacheRec10 = record F10: integer; N10: string; end;
  TCacheRec11 = record F11: integer; N11: string; end;
  TCacheRec12 = record F12: integer; N12: string; end;
  TCacheRec13 = record F13: integer; N13: string; end;
  TCacheRec14 = record F14: integer; N14: string; end;
  TCacheRec15 = record F15: integer; N15: string; end;
  TCacheRec16 = record F16: integer; N16: string; end;
  TCacheRec17 = record F17: integer; N17: string; end;
  TCacheRec18 = record F18: integer; N18: string; end;
  TCacheRec19 = record F19: integer; N19: string; end;
  TCacheRec20 = record F20: integer; N20: string; end;

  // Workers cannot call Assert: DUnitX collects failures on the thread running
  // the test. They tally instead, and the main thread asserts on the total.
  TStats = record
    Errors: integer;
    Mismatches: integer;
    FirstFail: string;
    procedure Note(const what: string);
    procedure Merge(const other: TStats);
  end;

  // delphi has no standalone generic routines, only generic methods - hence
  // the carrier record.
  TStep = record
    class procedure Run<T>(j: TJSONCodec; const v: T; const expected: UTF8String;
      var st: TStats); static;
  end;

procedure TStats.Note(const what: string);
begin
  if FirstFail = '' then FirstFail:= what;
end;

procedure TStats.Merge(const other: TStats);
begin
  inc(Errors,other.Errors);
  inc(Mismatches,other.Mismatches);
  if FirstFail = '' then FirstFail:= other.FirstFail;
end;

// the second marshal catches a parse-side entry pointing at the wrong type
class procedure TStep.Run<T>(j: TJSONCodec; const v: T; const expected: UTF8String; var st: TStats);
var
  s,s2: UTF8String;
  tmp: T;
  err: TJSONResult;
begin
  err:= j.Marshal(v,s);
  if err <> JSONOK then begin
    inc(st.Errors);
    st.Note(Format('marshal %s: err=%d',[GetTypeName(TypeInfo(T)),Ord(err)]));
    exit;
  end;
  if s <> expected then begin
    inc(st.Mismatches);
    st.Note(Format('marshal %s: got %s, want %s',
      [GetTypeName(TypeInfo(T)),string(s),string(expected)]));
    exit;
  end;

  err:= j.Unmarshal(s,tmp);
  if err <> JSONOK then begin
    inc(st.Errors);
    st.Note(Format('unmarshal %s: err=%d',[GetTypeName(TypeInfo(T)),Ord(err)]));
    exit;
  end;

  err:= j.Marshal(tmp,s2);
  if err <> JSONOK then begin
    inc(st.Errors);
    st.Note(Format('re-marshal %s: err=%d',[GetTypeName(TypeInfo(T)),Ord(err)]));
    exit;
  end;
  if s2 <> expected then begin
    inc(st.Mismatches);
    st.Note(Format('roundtrip %s: got %s, want %s',
      [GetTypeName(TypeInfo(T)),string(s2),string(expected)]));
  end;
end;

procedure RunAllTypes(j: TJSONCodec; var st: TStats; rounds: integer);
var
  v01: TCacheRec01;
  v02: TCacheRec02;
  v03: TCacheRec03;
  v04: TCacheRec04;
  v05: TCacheRec05;
  v06: TCacheRec06;
  v07: TCacheRec07;
  v08: TCacheRec08;
  v09: TCacheRec09;
  v10: TCacheRec10;
  v11: TCacheRec11;
  v12: TCacheRec12;
  v13: TCacheRec13;
  v14: TCacheRec14;
  v15: TCacheRec15;
  v16: TCacheRec16;
  v17: TCacheRec17;
  v18: TCacheRec18;
  v19: TCacheRec19;
  v20: TCacheRec20;
begin
  v01.F01:= 1; v01.N01:= 'n01';
  v02.F02:= 2; v02.N02:= 'n02';
  v03.F03:= 3; v03.N03:= 'n03';
  v04.F04:= 4; v04.N04:= 'n04';
  v05.F05:= 5; v05.N05:= 'n05';
  v06.F06:= 6; v06.N06:= 'n06';
  v07.F07:= 7; v07.N07:= 'n07';
  v08.F08:= 8; v08.N08:= 'n08';
  v09.F09:= 9; v09.N09:= 'n09';
  v10.F10:= 10; v10.N10:= 'n10';
  v11.F11:= 11; v11.N11:= 'n11';
  v12.F12:= 12; v12.N12:= 'n12';
  v13.F13:= 13; v13.N13:= 'n13';
  v14.F14:= 14; v14.N14:= 'n14';
  v15.F15:= 15; v15.N15:= 'n15';
  v16.F16:= 16; v16.N16:= 'n16';
  v17.F17:= 17; v17.N17:= 'n17';
  v18.F18:= 18; v18.N18:= 'n18';
  v19.F19:= 19; v19.N19:= 'n19';
  v20.F20:= 20; v20.N20:= 'n20';

  for var r:= 1 to rounds do begin
    TStep.Run<TCacheRec01>(j,v01,'{"F01":1,"N01":"n01"}',st);
    TStep.Run<TCacheRec02>(j,v02,'{"F02":2,"N02":"n02"}',st);
    TStep.Run<TCacheRec03>(j,v03,'{"F03":3,"N03":"n03"}',st);
    TStep.Run<TCacheRec04>(j,v04,'{"F04":4,"N04":"n04"}',st);
    TStep.Run<TCacheRec05>(j,v05,'{"F05":5,"N05":"n05"}',st);
    TStep.Run<TCacheRec06>(j,v06,'{"F06":6,"N06":"n06"}',st);
    TStep.Run<TCacheRec07>(j,v07,'{"F07":7,"N07":"n07"}',st);
    TStep.Run<TCacheRec08>(j,v08,'{"F08":8,"N08":"n08"}',st);
    TStep.Run<TCacheRec09>(j,v09,'{"F09":9,"N09":"n09"}',st);
    TStep.Run<TCacheRec10>(j,v10,'{"F10":10,"N10":"n10"}',st);
    TStep.Run<TCacheRec11>(j,v11,'{"F11":11,"N11":"n11"}',st);
    TStep.Run<TCacheRec12>(j,v12,'{"F12":12,"N12":"n12"}',st);
    TStep.Run<TCacheRec13>(j,v13,'{"F13":13,"N13":"n13"}',st);
    TStep.Run<TCacheRec14>(j,v14,'{"F14":14,"N14":"n14"}',st);
    TStep.Run<TCacheRec15>(j,v15,'{"F15":15,"N15":"n15"}',st);
    TStep.Run<TCacheRec16>(j,v16,'{"F16":16,"N16":"n16"}',st);
    TStep.Run<TCacheRec17>(j,v17,'{"F17":17,"N17":"n17"}',st);
    TStep.Run<TCacheRec18>(j,v18,'{"F18":18,"N18":"n18"}',st);
    TStep.Run<TCacheRec19>(j,v19,'{"F19":19,"N19":"n19"}',st);
    TStep.Run<TCacheRec20>(j,v20,'{"F20":20,"N20":"n20"}',st);
  end;
end;

type
  TCacheWorker = class(TThread)
  private
    FJSON: TJSONCodec;
    FGate: TEvent;
    FDone: TEvent;
    FStats: TStats;
  protected
    procedure Execute; override;
  end;

procedure TCacheWorker.Execute;
begin
  try
    FGate.WaitFor(INFINITE);
    RunAllTypes(FJSON,FStats,ROUNDS);
  finally
    FDone.SetEvent;
  end;
end;

// 20 distinct types, capacity 16: the 17th forces grow-and-retire, and entries
// handed out before must stay valid. Keep it past 16
procedure TTypeCacheTest.TestCacheGrowsPastInitialCapacity;
var
  j: TJSONCodec;
  st: TStats;
begin
  st:= Default(TStats);
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    RunAllTypes(j,st,2);
  finally
    j.Free;
  end;

  Assert.AreEqual(0,st.Errors,'errors: '+st.FirstFail);
  Assert.AreEqual(0,st.Mismatches,'mismatches: '+st.FirstFail);
end;

// all workers released onto an empty cache, the only way to reach the double-check
// after the lock. Bounded wait: a held lock fails the test instead of hanging it;
// stuck threads are left alone, they own a lock nobody can release
procedure TTypeCacheTest.TestConcurrentAccessToColdCache;
var
  j: TJSONCodec;
  gate: TEvent;
  ws: array[0..WORKERS-1] of TCacheWorker;
  st: TStats;
  i,attempt: integer;
  stuck: boolean;
begin
  st:= Default(TStats);
  stuck:= false;

  for attempt:= 1 to ATTEMPTS do begin
    j:= TJSONCodec.Create(JSONDefaultConfig);
    gate:= TEvent.Create(nil,true,false,'');
    try
      for i:= 0 to High(ws) do begin
        ws[i]:= TCacheWorker.Create(true);
        ws[i].FreeOnTerminate:= false;
        ws[i].FJSON:= j;
        ws[i].FGate:= gate;
        ws[i].FDone:= TEvent.Create(nil,true,false,'');
        ws[i].FStats:= Default(TStats);
        ws[i].Start;
      end;

      Sleep(15);         // let every worker reach the gate
      gate.SetEvent;     // ... and release them onto the cold cache together

      for i:= 0 to High(ws) do begin
        // one stuck worker means the lock is gone for good, so the rest would
        // only burn another timeout each: give up on the first.
        if ws[i].FDone.WaitFor(WORKER_TIMEOUT) <> wrSignaled then begin
          stuck:= true;
          break;
        end;
        ws[i].WaitFor;
        st.Merge(ws[i].FStats);
        ws[i].FDone.Free;
        ws[i].Free;
      end;
    finally
      // when stuck, the workers still reference the gate and the TJSONCodec, and
      // they are never coming back - so everything here is leaked on purpose.
      if not stuck then begin
        gate.Free;
        j.Free;
      end;
    end;

    if stuck then break;
  end;

  Assert.IsFalse(stuck,
    'worker did not finish within 30s - the type cache lock is most '+
    'likely being held across an early exit in TTypeCache.Get');
  Assert.AreEqual(0,st.Errors,'errors: '+st.FirstFail);
  Assert.AreEqual(0,st.Mismatches,'mismatches: '+st.FirstFail);
end;


initialization
  TDUnitX.RegisterTestFixture(TTypeCacheTest);

end.
