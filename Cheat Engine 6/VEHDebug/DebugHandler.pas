unit DebugHandler;

{$mode delphi}

interface

uses
  windows, Classes, SysUtils, syncobjs;


function Handler(ExceptionInfo: PEXCEPTION_POINTERS): LONG; stdcall;
function InternalHandler(ExceptionInfo: PEXCEPTION_POINTERS; threadid: dword): LONG;
procedure testandfixcs_start;
procedure testandfixcs_final;

implementation

uses init;

var HandlerCS: TCRITICALSECTION;
  emergency: THandle; //event that is set when

procedure testandfixcs_start;
begin
  setevent(emergency);
end;

procedure testandfixcs_final;
begin
  handlercs.enter;
  handlercs.leave;
  resetevent(emergency);
end;


function InternalHandler(ExceptionInfo: PEXCEPTION_POINTERS; threadid: dword): LONG;
var i: integer;
  eventhandles: array [0..1] of THandle;
  wr: dword;
begin
   HandlerCS.enter; //block any other thread that has an single step exception untill this is handles

   //fill in the exception and context structures
   {$ifdef cpu64}
   VEHSharedMem.Exception64.ExceptionCode:=ExceptionInfo.ExceptionRecord.ExceptionCode;
   VEHSharedMem.Exception64.ExceptionFlags:=ExceptionInfo.ExceptionRecord.ExceptionFlags;
   VEHSharedMem.Exception64.ExceptionRecord:=DWORD64(ExceptionInfo.ExceptionRecord.ExceptionRecord);
   VEHSharedMem.Exception64.NumberParameters:=ExceptionInfo.ExceptionRecord.NumberParameters;
   for i:=0 to ExceptionInfo.ExceptionRecord.NumberParameters do
     VEHSharedMem.Exception64.ExceptionInformation[i]:=ExceptionInfo.ExceptionRecord.ExceptionInformation[i];
   {$else}
   VEHSharedMem.Exception32.ExceptionCode:=ExceptionInfo.ExceptionRecord.ExceptionCode;
   VEHSharedMem.Exception32.ExceptionFlags:=ExceptionInfo.ExceptionRecord.ExceptionFlags;
   VEHSharedMem.Exception32.ExceptionRecord:=DWORD(ExceptionInfo.ExceptionRecord.ExceptionRecord);
   VEHSharedMem.Exception32.NumberParameters:=ExceptionInfo.ExceptionRecord.NumberParameters;
   for i:=0 to ExceptionInfo.ExceptionRecord.NumberParameters do
     VEHSharedMem.Exception32.ExceptionInformation[i]:=ExceptionInfo.ExceptionRecord.ExceptionInformation[i];
   {$endif}

   //setup the context
   CopyMemory(@VEHSharedMem.CurrentContext[0],ExceptionInfo.ContextRecord,sizeof(TCONTEXT));

   VEHSharedMem.ProcessID:=GetCurrentProcessId;
   VEHSharedMem.ThreadID:=threadid;

   SetEvent(VEHSharedMem.HasDebugEvent);

   eventhandles[0]:=VEHSharedMem.HasHandledDebugEvent;
   eventhandles[1]:=emergency;

   wr:=WaitForMultipleObjects(2, @eventhandles, false, INFINITE);

   i:=wr -WAIT_OBJECT_0;
   if i=0 then //hashandleddebugevent has been set.  After ce is done with it use the new context
     CopyMemory(ExceptionInfo.ContextRecord,@VEHSharedMem.CurrentContext[0],sizeof(TCONTEXT))
   else
   begin
     result:=EXCEPTION_CONTINUE_EXECUTION; //something went wrong VEHSharedmem might even be broken
     HandlerCS.Leave;
     exit;
   end;


   //depending on user options either return EXCEPTION_CONTINUE_SEARCH or EXCEPTION_CONTINUE_EXECUTION
   if VEHSharedMem.ContinueMethod=DBG_CONTINUE then
     result:=EXCEPTION_CONTINUE_EXECUTION
   else
     result:=EXCEPTION_CONTINUE_SEARCH;

   HandlerCS.Leave;

end;

function Handler(ExceptionInfo: PEXCEPTION_POINTERS): LONG; stdcall;
begin
  result:=InternalHandler(ExceptionInfo, getCurrentThreadID);
end;

initialization
  HandlerCS:=TCriticalSection.create;
  emergency:=CreateEvent(nil,true, false,'');


finalization
  if HandlerCS<>nil then
    HandlerCS.free;

end.

