#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

// Release the single-instance mutex before elevating/restarting so the new
// process can acquire it immediately.
void RunnerReleaseSingleInstanceMutex();

#endif  // RUNNER_SINGLE_INSTANCE_H_
