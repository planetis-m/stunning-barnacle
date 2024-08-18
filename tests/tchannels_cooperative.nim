import std/[os, osproc], sync/channels

const
  NTasks = 256'i16 # int16 allows using this in a Set
  SleepDurationMS = 3
  sentmsg = "task sent"

type
  Payload = tuple[chan: Chan[int16], idx: int16]

var
  sentmessages = newSeqOfCap[string](NTasks)
  receivedmessages = newSeqOfCap[int16](NTasks)

# A prototype of a task executing thread
proc runner(tasksCh: Chan[Payload]) {.thread.} =
  var p: Payload
  while true:
    tasksCh.recv(p) # Get a message from the main thread
    if p.idx == -1: break # Check for an ad hoc stop signal
    else:
      sleep(SleepDurationMS) # Hard work
      p.chan.send(p.idx) # Notify a consumer

# A single thread receiving result from runner threads
proc consumer(args: tuple[resultsCh: Chan[int16], tasks: int16]) {.thread.} =
  var idx: int16
  for _ in 0..<args.tasks: # We know the number of tasks and wait for them all
    args.resultsCh.recv(idx)
    {.gcsafe.}: # Don't do this. Here we know it's an exclusive access
      receivedmessages.add(idx) # Store which task was completed

proc main(chanSize: Natural) =
  sentmessages.setLen(0)
  receivedmessages.setLen(0)
  var
    taskThreads = newSeq[Thread[Chan[Payload]]](countProcessors())
    tasksCh = newChan[Payload](chanSize)
    consumerTh: Thread[(Chan[int16], int16)]
    resultsCh = newChan[int16](chanSize)

  # Consumer must be ready first to not block
  createThread(consumerTh, consumer, (resultsCh, NTasks))
  # Start runner threads
  for i in 0..high(taskThreads): createThread(taskThreads[i], runner, tasksCh)
  # Loop iterating fake data
  for idx in 0'i16..<NTasks:
    tasksCh.send((resultsCh, idx))
    sentmessages.add(sentmsg)

  for _ in taskThreads: # Stopping worker threads
    tasksCh.send((resultsCh, -1'i16)) # A thread can't get more than 1 stop signal
  joinThreads(taskThreads)
  joinThread(consumerTh)

#------------------------------------------------------------------------------

template runTests(bufferSize: Positive) =
  main(bufferSize)

  doAssert sentmessages.len == NTasks
  doAssert receivedmessages.len == Ntasks
  doAssert sentmessages[^1] == sentmsg

  var set = {0..NTasks-1}
  for i in receivedmessages: set.excl(i)
  doAssert set == {}


block buffered_channels:
  runTests(bufferSize = 2)

block unbuffered_channels:
  runTests(bufferSize = 1)
