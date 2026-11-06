unit TestConcurrency;

// A warm instance and the widest mix of types, from several threads at once;
// TestTypeCache covers the cold cache. Every thread must produce the single-
// threaded output byte for byte. The expectations are captured on the calling
// thread first, not written as literals - that keeps the test independent of the
// time zone and of the config.

interface

uses
  DUnitX.TestFramework,
  encoding.json;

type
  TWorkKind = (wkAlpha, wkBeta, wkGamma);

  TWorkRecord = record
    Id: integer;
    Name: string;
    Ratio: double;
    Flag: boolean;
    Kind: TWorkKind;
  end;

  TWorkNested = record
    Title: string;
    Inner: TWorkRecord;
  end;

  TFiveInts = array[0..4] of integer;

  [TestFixture]
  TConcurrencyTest = class
  private
    procedure HammerInstance(j: TJSONCodec; const what: string);
  public
    [Test] procedure TestWarmInstanceSurvivesConcurrentRoundTrips;
    [Test] procedure TestGlobalInstanceSurvivesConcurrentRoundTrips;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.SyncObjs,
  System.TypInfo,
  System.Generics.Collections;

const
  WORKERS        = 8;      // threads hammering one instance at the same time
  ROUNDS         = 40;     // passes over every type per worker
  WORKER_TIMEOUT = 30000;  // bounded, so a deadlock fails the suite instead of hanging it

type
  // Workers cannot call Assert - DUnitX collects failures on the thread running
  // the test. They tally instead, and the main thread asserts on the total.
  TStats = record
    Errors: integer;
    Mismatches: integer;
    FirstFail: string;
    procedure Failed(const what: string);
    procedure Differed(const what: string);
    procedure Merge(const other: TStats);
  end;

  // one expected document per type in the round
  TExpectations = record
    Rec: UTF8String;
    Nested: UTF8String;
    DynArray: UTF8String;
    StaticArray: UTF8String;
    Moment: UTF8String;
    Id: UTF8String;
    Vari: UTF8String;
    List: UTF8String;
    Dict: UTF8String;
    Strings: UTF8String;
  end;

procedure TStats.Failed(const what: string);
begin
  Inc(Errors);
  if FirstFail = '' then FirstFail:= what;
end;

procedure TStats.Differed(const what: string);
begin
  Inc(Mismatches);
  if FirstFail = '' then FirstFail:= what;
end;

procedure TStats.Merge(const other: TStats);
begin
  Inc(Errors,other.Errors);
  Inc(Mismatches,other.Mismatches);
  if (FirstFail = '') and (other.FirstFail <> '') then FirstFail:= other.FirstFail;
end;


// Delphi has no standalone generic routines, only generic methods - hence the
// carrier record, same trick TestTypeCache uses.
type
  TStep = record
    class procedure Run<T>(j: TJSONCodec; const v: T; var want: UTF8String;
      capture: boolean; var st: TStats); static;
  end;

// marshal -> compare (or capture) -> unmarshal -> marshal again -> compare.
// the second marshal is what catches a decode that quietly loses something.
class procedure TStep.Run<T>(j: TJSONCodec; const v: T; var want: UTF8String;
  capture: boolean; var st: TStats);
var
  s,s2: UTF8String;
  tmp: T;
  err: TJSONResult;
  name: string;
begin
  name:= string(GetTypeName(TypeInfo(T)));

  err:= j.Marshal(v,s);
  if err <> JSONOK then begin
    st.Failed(Format('marshal %s -> %d',[name,ord(err)]));
    exit;
  end;

  if capture then
    want:= s
  else if s <> want then begin
    st.Differed(Format('marshal %s: got %s, want %s',[name,string(s),string(want)]));
    exit;
  end;

  tmp:= Default(T);
  err:= j.Unmarshal(s,tmp);
  if err <> JSONOK then begin
    st.Failed(Format('unmarshal %s -> %d',[name,ord(err)]));
    exit;
  end;

  err:= j.Marshal(tmp,s2);
  if err <> JSONOK then begin
    st.Failed(Format('re-marshal %s -> %d',[name,ord(err)]));
    exit;
  end;

  if s2 <> want then
    st.Differed(Format('roundtrip %s: got %s, want %s',[name,string(s2),string(want)]));
end;


// the class cases longhand: instances made and freed inside the worker, the
// decode side building its own destination
procedure RunList(j: TJSONCodec; var want: UTF8String; capture: boolean; var st: TStats);
var
  src,dst: TList<integer>;
  s,s2: UTF8String;
  err: TJSONResult;
begin
  src:= TList<integer>.Create;
  try
    src.Add(11); src.Add(22); src.Add(33);
    err:= j.Marshal(src,s);
  finally
    src.Free;
  end;
  if err <> JSONOK then begin st.Failed(Format('marshal TList -> %d',[ord(err)])); exit; end;

  if capture then
    want:= s
  else if s <> want then begin
    st.Differed(Format('marshal TList: got %s, want %s',[string(s),string(want)]));
    exit;
  end;

  dst:= nil;
  try
    err:= j.Unmarshal(s,dst);
    if err <> JSONOK then begin st.Failed(Format('unmarshal TList -> %d',[ord(err)])); exit; end;
    err:= j.Marshal(dst,s2);
  finally
    dst.Free;
  end;
  if err <> JSONOK then begin st.Failed(Format('re-marshal TList -> %d',[ord(err)])); exit; end;

  if s2 <> want then
    st.Differed(Format('roundtrip TList: got %s, want %s',[string(s2),string(want)]));
end;

// inserted out of order: the encoder sorts the keys - on every thread at once
procedure RunDict(j: TJSONCodec; var want: UTF8String; capture: boolean; var st: TStats);
var
  src,dst: TDictionary<string,integer>;
  s,s2: UTF8String;
  err: TJSONResult;
begin
  src:= TDictionary<string,integer>.Create;
  try
    src.Add('zulu',1);
    src.Add('alpha',2);
    src.Add('mike',3);
    err:= j.Marshal(src,s);
  finally
    src.Free;
  end;
  if err <> JSONOK then begin st.Failed(Format('marshal TDictionary -> %d',[ord(err)])); exit; end;

  if capture then
    want:= s
  else if s <> want then begin
    st.Differed(Format('marshal TDictionary: got %s, want %s',[string(s),string(want)]));
    exit;
  end;

  dst:= nil;
  try
    err:= j.Unmarshal(s,dst);
    if err <> JSONOK then begin st.Failed(Format('unmarshal TDictionary -> %d',[ord(err)])); exit; end;
    err:= j.Marshal(dst,s2);
  finally
    dst.Free;
  end;
  if err <> JSONOK then begin st.Failed(Format('re-marshal TDictionary -> %d',[ord(err)])); exit; end;

  if s2 <> want then
    st.Differed(Format('roundtrip TDictionary: got %s, want %s',[string(s2),string(want)]));
end;

// no '=' in the entries, so this stays in the list-of-strings mode rather than
// the key-value one
procedure RunStrings(j: TJSONCodec; var want: UTF8String; capture: boolean; var st: TStats);
var
  src,dst: TStringList;
  s,s2: UTF8String;
  err: TJSONResult;
begin
  src:= TStringList.Create;
  try
    src.Add('alpha'); src.Add('beta'); src.Add('gamma');
    err:= j.Marshal(src,s);
  finally
    src.Free;
  end;
  if err <> JSONOK then begin st.Failed(Format('marshal TStrings -> %d',[ord(err)])); exit; end;

  if capture then
    want:= s
  else if s <> want then begin
    st.Differed(Format('marshal TStrings: got %s, want %s',[string(s),string(want)]));
    exit;
  end;

  dst:= nil;
  try
    err:= j.Unmarshal(s,dst);
    if err <> JSONOK then begin st.Failed(Format('unmarshal TStrings -> %d',[ord(err)])); exit; end;
    err:= j.Marshal(dst,s2);
  finally
    dst.Free;
  end;
  if err <> JSONOK then begin st.Failed(Format('re-marshal TStrings -> %d',[ord(err)])); exit; end;

  if s2 <> want then
    st.Differed(Format('roundtrip TStrings: got %s, want %s',[string(s2),string(want)]));
end;


// one pass over every type: with capture on the calling thread to fill "want"
// (and warm the caches), then by the workers
procedure RunRound(j: TJSONCodec; var want: TExpectations; capture: boolean; var st: TStats);
var
  rec: TWorkRecord;
  nested: TWorkNested;
  dyn: TArray<integer>;
  stat: TFiveInts;
  moment: TDateTime;
  id: TGUID;
  vari: Variant;
  i: integer;
begin
  rec.Id:= 4711;
  rec.Name:= 'a name with "quotes" and a backslash';
  rec.Ratio:= 1.5;
  rec.Flag:= true;
  rec.Kind:= wkBeta;

  nested.Title:= 'outer';
  nested.Inner:= rec;

  dyn:= [1,2,3,4,5,6,7,8];
  for i:= 0 to High(stat) do stat[i]:= i*i;

  moment:= EncodeDateTime(2024,6,9,12,30,45,123);
  id:= StringToGUID('{e0c119de-4bdf-418f-ac93-4f150d72e1b0}');
  vari:= 12345;

  TStep.Run<TWorkRecord>(j,rec,want.Rec,capture,st);
  TStep.Run<TWorkNested>(j,nested,want.Nested,capture,st);
  TStep.Run<TArray<integer>>(j,dyn,want.DynArray,capture,st);
  TStep.Run<TFiveInts>(j,stat,want.StaticArray,capture,st);
  TStep.Run<TDateTime>(j,moment,want.Moment,capture,st);
  TStep.Run<TGUID>(j,id,want.Id,capture,st);
  TStep.Run<Variant>(j,vari,want.Vari,capture,st);

  RunList(j,want.List,capture,st);
  RunDict(j,want.Dict,capture,st);
  RunStrings(j,want.Strings,capture,st);
end;


type
  TRoundTripWorker = class(TThread)
  private
    FJSON: TJSONCodec;
    FGate: TEvent;
    FDone: TEvent;
    FWant: TExpectations;
    FStats: TStats;
  protected
    procedure Execute; override;
  end;

procedure TRoundTripWorker.Execute;
var
  i: integer;
begin
  try
    FGate.WaitFor(INFINITE);
    for i:= 1 to ROUNDS do
      RunRound(FJSON,FWant,false,FStats);
  finally
    FDone.SetEvent;
  end;
end;


procedure TConcurrencyTest.HammerInstance(j: TJSONCodec; const what: string);
var
  want: TExpectations;
  baseline,st: TStats;
  gate: TEvent;
  ws: array[0..WORKERS-1] of TRoundTripWorker;
  i: integer;
  stuck: boolean;
begin
  baseline:= Default(TStats);
  st:= Default(TStats);
  want:= Default(TExpectations);
  stuck:= false;

  // single-threaded first: this is what the workers have to agree with, and it
  // leaves the type caches warm, which is the state under test
  RunRound(j,want,true,baseline);
  Assert.AreEqual(0,baseline.Errors,
    what + ': the single-threaded pass already failed - ' + baseline.FirstFail);

  gate:= TEvent.Create(nil,true,false,'');
  try
    for i:= 0 to High(ws) do begin
      ws[i]:= TRoundTripWorker.Create(true);
      ws[i].FreeOnTerminate:= false;
      ws[i].FJSON:= j;
      ws[i].FGate:= gate;
      ws[i].FDone:= TEvent.Create(nil,true,false,'');
      ws[i].FWant:= want;
      ws[i].FStats:= Default(TStats);
      ws[i].Start;
    end;

    Sleep(15);        // let every worker reach the gate
    gate.SetEvent;    // ... and release them together

    for i:= 0 to High(ws) do begin
      // one stuck worker means the instance is wedged for good, so the rest
      // would only burn another timeout each: give up on the first
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
    // when stuck, the workers still hold the gate and the instance and are
    // never coming back - everything here is leaked on purpose
    if not stuck then gate.Free;
  end;

  Assert.IsFalse(stuck,
    what + ': a worker did not finish within 30s - marshalling on one instance '+
    'from several threads has deadlocked');
  Assert.AreEqual(0,st.Errors,what + ': errors - ' + st.FirstFail);
  Assert.AreEqual(0,st.Mismatches,what + ': mismatches - ' + st.FirstFail);
end;


procedure TConcurrencyTest.TestWarmInstanceSurvivesConcurrentRoundTrips;
var
  j: TJSONCodec;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    HammerInstance(j,'own instance');
  finally
    j.Free;
  end;
end;

// the global instance is the one the README actually names, and it is the one
// an application shares without thinking about it
procedure TConcurrencyTest.TestGlobalInstanceSurvivesConcurrentRoundTrips;
begin
  HammerInstance(JSON,'global JSON instance');
end;

initialization
  TDUnitX.RegisterTestFixture(TConcurrencyTest);

end.
