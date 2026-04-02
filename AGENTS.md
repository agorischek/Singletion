# Agent Instructions

- Unless specifically instructed not to, after you make a code change, you should deploy the updated app, commit, and push.
- To deploy the updated app, first terminate any existing `Singletion` processes so only one instance remains running. Prefer `pkill -f '/Singletion.app/Contents/MacOS/Singletion' || true`.
- After terminating `Singletion`, run `./install-singletion.sh` from the repo root. That script rebuilds the app, copies the new build output to `~/Applications/Singletion.app`, and relaunches it.
- After the deploy succeeds, commit your changes and push them.
