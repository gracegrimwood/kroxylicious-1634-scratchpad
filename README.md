# Grace's KEK Invalidation Race/Missing Logs Scratchpad

This repo is really just a collection of files I used and collected while testing [kroxylicious/kroxylicious#1526](https://github.com/kroxylicious/kroxylicious/issues/1526) and [kroxylicious/kroxylicious#1634](https://github.com/kroxylicious/kroxylicious/issues/1634). None of this is polished or terribly well-written, it's mostly just here as reference for anyone who may want to reproduce or double-check my work. I wouldn't recommend running or deploying anything in here without properly checking it over first, there's some bits that I've just thrown together to get things working for me so parts of it (i.e. the scripts) possibly won't work for anyone else.

Many of the YAML files here are borrowed and modified from ones in the [Kroxylicious](https://github.com/kroxylicious/kroxylicious) repository.

## Building the Kroxytester image

The image is built with Podman on top of an official Apache Kafka image (Kafka 3.8 is what I've got in the Dockerfile because at the time it's what Kroxylicious supported, but I imagine just about any Kafka release version should work). It's not particularly sophisticated; it logs a start time for future reference (so you can check in the logs afterwards when the testers started vs when the proxy noticed), then runs Kafka's in-built `kafka-producer-perf-test.sh` (the values are configurable via env vars, but the defaults are mostly what I used) to throw a bunch of stuff at the proxy, then it logs an end time and loops forever doing nothing until killed by either you or k8s. The looping is to stop it from restarting the perf test script, which makes it impossible to tell what volume of messages and requests went through Kroxylicious and ruins the whole test.

You can build the Kroxytester images yourself like this:

```sh
cd kroxytester/image/
podman build --file=Dockerfile
```

If you're building them on Darwin to run on OpenShift you'll want to specify the `--platform=linux/arm64` flag as well.

## The `kroxy_load_test.sh` script

This is the aforementioned hacky part. If you look at it you can see the part where I started trying to make it all nice and sophisticated and configurable, and a few lines down from that you'll see the point where I said "screw it, it just needs to work". It may not be terribly long, but copy-pasted code and platform-specific hacks abound-- the stuff with timestamp conversion and arithmetic in particular is a Darwin thing and almost certainly works very ~~sensibly~~ differently on Linux. Take this script with an industrial quantity of salt, and maybe just write your own ~~better~~ version if you decide you need it to actually work.

### Before the script runs you will need:

- A kubernetes cluster. I used this with ROSA and Minikube, but note that the missing logs issue probably won't occur on Minikube because it's hard to get the throughput and log volume required for the issue to become evident when run locally on machines with more limited hardware.
- A Kafka cluster, either on the Kubernetes cluster or accessible from within it. Note all the config files here expect a standard Strimzi-deployed cluster in the same Kubernetes environment as Kroxylicious.
- A `kroxylicious` namespace on that Kubernetes cluster
- A `kroxytest` namespace on that Kubernetes cluster
- All the necessary values and config for [running the Kroxylicious Record Encryption filter with AWS KMS](https://kroxylicious.io/docs/v0.9.0/#assembly-aws-kms-proxy), which is then configured in [./kroxylicious/kroxylicious-config.yaml](./kroxylicious/kroxylicious-config.yaml). You may find following the Kroxylicious Record Encryption k8s example easiest for this. _Note: **don't** use a template selector here if you're trying to reproduce the `RequestNotSatisfiable` KEK invalidation race condition, or it won't work (reliably)._
- The [./kroxylicious/kroxylicious-config.yaml](./kroxylicious/kroxylicious-config.yaml) and [./kroxylicious/kroxylicious-service.yaml](./kroxylicious/kroxylicious-service.yaml) files applied in the `kroxylicious` namespace.
- A built copy of the Kroxytester image (or grab one of mine from [quay.io](quay.io/ggrimwoo/kroxy-perf-test) if you'd like)

### A summary of what it does so you don't have to read the code:

Some of the timings here will vary based on your infra and network, so adjust as needed.

_Substitute `oc` for `kubectl` here if that's your preferred flavour of k8s CLI._

1. Resets the Kroxytester deployment to default values with 0 replicas with `oc apply -ns kroxytest -f kroxytester_defaults_0repl.yaml`
2. Resets the Kroxylicious deployment to default values with 0 replicas with `oc apply -ns kroxylicious -f kroxylicious-proxy_defaults_0repl.yaml`
3. Logs a start time
4. Starts a Kroxylicious instance with `oc apply -ns kroxylicious -f kroxylicious-proxy_ROOT-DEBUG_1repl.yaml`
    _The difference between the `ROOT-DEBUG` deployment files and the `defaults` deployment files is that the `ROOT-DEBUG` files include the following:_
    ```yaml
    env:
    - name: KROXYLICIOUS_ROOT_LOG_LEVEL
      value: DEBUG
    ```
    _For the `APP-DEBUG` files it's the same thing but we replace `KROXYLICIOUS_ROOT_LOG_LEVEL` with `KROXYLICIOUS_APP_LOG_LEVEL` instead. The `defaults` files have no env vars set. I just changed which yaml file this line referenced in the script when I wanted to alter this but there's a thousand better ways to do this, and you should pick one of those ways instead._
5. Sleeps 10 seconds (roughly the time it takes for a proxy pod to start on ROSA)
    _Would have been better to use `oc wait` here but I found sometimes the script would run ahead and query the conditions of the deployment before it had finished being created and I decided `sleep` was easier than debugging._
6. Starts a background process to capture the proxy pod logs in the background with:
    ```sh
    KROXY_POD=$(oc get pods -n "${KROXY_NS}" -o name | sed 's/pod\///g')
    oc logs -n kroxylicious "${KROXY_POD}" -f > "logs/$(date -jf "%s" "${EXEC_START_TIME}" +"%Y%m%d_%H%M%S")_${KROXY_POD}.log" &
    ```
    _Note: we don't actually check how many pods are returned by that first `oc get pods`, so if you're running other things in the `kroxylicious` namespace this might blow up. This is kind of bad and probably you want to actually check this but I was running this in a fresh environment and deleting namespaces as I went so it wasn't an issue for me._
7. Starts five Kroxytester pods with `oc apply -ns kroxytest -f kroxytester_defaults_5repl.yaml`
    _I didn't have any fancypants config to change between deployments in this one, so the only thing that changes here is the number of replicas._
8. Waits for 30 seconds for the Kroxytester deployment to become ready with `oc wait --for=condition=Ready -n kroxytest deploy/kroxytester --timeout=30s`
    _This will time out because the deployment won't ever enter a ready state, but that's fine because all we really needed to do was wait for roughly 30s for the containers to start._
9. Starts background processes to capture the Kroxytester pods logs with:
    ```sh
    oc get pods -n "${TESTER_NS}" -o name | sed 's/pod\///g' | while read -r TESTER_POD; do
      oc logs -n "${TESTER_NS}" "${TESTER_POD}" -f > "logs/$(date -jf "%s" "${EXEC_START_TIME}" +"%Y%m%d_%H%M%S")_${TESTER_POD}.log" &
    done
    ```
10. Sleeps 140 seconds (roughly the time it takes the Kroxytesters to run the rest of their perf script and start looping)
11. Resets the Kroxytester deployment to default values with 0 replicas with `oc apply -ns kroxytest -f kroxytester_defaults_0repl.yaml`
    _We're scaling down the Kroxytester pods first so that Kroxylicious has a little time to settle and we capture the logs returning to baseline before we kill it. When the pods are scaled down the background processes we created earlier should self-terminate._
12. Sleeps 30 seconds
13. Resets the Kroxylicious deployment to default values with 0 replicas with `oc apply -ns kroxylicious -f kroxylicious-proxy_defaults_0repl.yaml`
