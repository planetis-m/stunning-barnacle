#
#
#            Nim's Runtime Library
#        (c) Copyright 2023 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.

## Once for Nim.

runnableExamples:

  type
    Singleton = object
      data: int

  var
    counter = 1
    instance: ptr Singleton
    exceptionOccurred = false
    o = createOnce()

  proc getInstance(): ptr Singleton =
    once(o):
      if not exceptionOccurred:
        # Simulate an exception on the first call
        exceptionOccurred = true
        raise newException(ValueError, "Simulated error")
      instance = createSharedU(Singleton)
      instance.data = counter
      inc counter
    result = instance

  proc worker {.thread.} =
    try:
      for i in 1..1000:
        let inst = getInstance()
        assert inst.data == 1
    except ValueError:
      echo "Caught expected ValueError"

  var threads: array[10, Thread[void]]
  for i in 0..<10:
    createThread(threads[i], worker)
  joinThreads(threads)
  deallocShared(instance)
  echo "All threads completed"

import std / locks

type
  Once* = object
    ## Once is a type that allows you to execute a block of code exactly once.
    ## The first call to `once` will execute the block of code and all other
    ## calls will be ignored. All concurrent calls to `once` are guaranteed to
    ## observe any side-effects made by the active call, with no additional
    ## synchronization.
    state: int
    L: Lock
    c: Cond

const
  Unset = 0
  Pending = 1
  Complete = -1

when defined(nimAllowNonVarDestructor):
  proc `=destroy`*(o: Once) {.inline.} =
    deinitLock(o.L)
    deinitCond(o.c)
else:
  proc `=destroy`*(o: var Once) {.inline.} =
    deinitLock(o.L)
    deinitCond(o.c)

proc `=sink`*(dest: var Once; source: Once) {.error.}
proc `=copy`*(dest: var Once; source: Once) {.error.}
proc `=dup`*(source: Once): Once {.error.}

proc createOnce*(): Once =
  result = default(Once)
  initLock(result.L)
  initCond(result.c)

template once*(o: Once, body: untyped) =
  ## Executes `body` exactly once.
  acquire(o.L)
  while o.state == Pending:
    wait(o.c, o.L)
  if o.state == Unset:
    o.state = Pending
    release(o.L)
    try:
      body
      acquire(o.L)
      o.state = Complete
      broadcast(o.c)
      release(o.L)
    except:
      acquire(o.L)
      o.state = Unset
      broadcast(o.c)
      release(o.L)
      raise
  else:
    release(o.L)
