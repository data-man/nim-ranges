## Stack-allocated arrays should be used with great care.
##
## They pose several major risks:
##
## 1. They should not be used inside resumable procs
##    (i.e. closure iterators and async procs)
##
##    Future versions of the library may automatically
##    detect such usages and flag them as errors
##
## 2. The user code should be certain that enough stack space
##    is available for the allocation and there will be enough
##    room for additional calls after the allocation.
##
##    Future versions of this library may provide checks
##
##    Please note that the stack size on certain platforms
##    may be very small (e.g. 8 to 32 kb on some Android versions)
##
## Before using alloca-backed arrays, consider using:
##
## 1. A regular stack array with a reasonable size
##
## 2. A global {.threadvar.} sequence that can be resized when
##    needed (only in non-reentrant procs)
##
## Other possible future directions:
##
## Instead of `alloca`, we may start using a shadow stack that will be much
## harder to overflow. This will work by allocating a very large chunk of the
## address space at program init (e.g. 1TB on a 64-bit system) and then by
## gradually committing the individual pages to memory as they are requested.
##
## Such a scheme will even allow us to resize the stack array on demand
## in situations where the final size is not known upfront. With a resizing
## factor of 2, we'll never waste more than 50% of the memory which should
## be reasonable for short-lived allocations.
##

type
  StackArray*[T] = ptr object
    bufferLen: int32
    buffer: UncheckedArray[T]

proc alloca(n: int): pointer {.importc, header: "<alloca.h>".}

proc raiseRangeError(s: string) =
  raise newException(RangeError, s)

proc raiseOutOfRange =
  raiseRangeError "index out of range"

template len*(a: StackArray): int =
  int(a.bufferLen)

template high*(a: StackArray): int =
  int(a.bufferLen) - 1

template low*(a: StackArray): int =
  0

template `[]`*(a: StackArray, i: int): auto =
  if i < 0 or i >= a.len: raiseOutOfRange()
  a.buffer[i]

proc `[]=`*(a: StackArray, i: int, val: a.T) =
  if i < 0 or i >= a.len: raiseOutOfRange()
  a.buffer[i] = val

template `[]`*(a: StackArray, i: BackwardsIndex): auto =
  if int(i) < 1 or int(i) > a.len: raiseOutOfRange()
  a.buffer[a.len - int(i)]

proc `[]=`*(a: StackArray, i: BackwardsIndex, val: a.T) =
  if int(i) < 1 or int(i) > a.len: raiseOutOfRange()
  a.buffer[a.len - int(i)] = val

iterator items*(a: StackArray): a.T =
  for i in 0 .. a.high:
    yield a.buffer[i]

iterator mitems*(a: var StackArray): var a.T =
  for i in 0 .. a.high:
    yield a.buffer[i]

iterator pairs*(a: StackArray): a.T =
  for i in 0 .. a.high:
    yield (i, a.buffer[i])

iterator mpairs*(a: var StackArray): (int, var a.T) =
  for i in 0 .. a.high:
    yield (i, a.buffer[i])

template allocStackArray*(T: typedesc, size: int): auto =
  if size < 0: raiseRangeError "allocation with a negative size"
  # XXX: is it possible to perform a stack size check before calling `alloca`?
  # On thread init, Nim may record the base address and the capacity of the stack,
  # so in theory we can verify that we still have enough room for the allocation.
  # Research this.
  var
    bufferSize = size * sizeof(T)
    totalSize = sizeof(int32) + bufferSize
    arr = cast[StackArray[T]](alloca(totalSize))
  zeroMem(addr arr.buffer[0], bufferSize)
  arr.bufferLen = size
  arr

template toOpenArray*(a: StackArray): auto =
  toOpenArray(a.buffer, 0, a.high)

template toOpenArray*(a: StackArray, first: int): auto =
  if first < 0 or first >= a.len: raiseOutOfRange()
  toOpenArray(a.buffer, first, a.high)

template toOpenArray*(a: StackArray, first, last: int): auto =
  if first < 0 or first >= last or last <= a.len: raiseOutOfRange()
  toOpenArray(a.buffer, first, last)

