import json
import os
import re
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_KEY = "0x" + (1).to_bytes(32, "big").hex()
DIRECT_CALL_DEPTH = 1
SUCCESSFUL_RECEIPT_STATUS = 1


def showcase_calls(build):
    output = subprocess.check_output([
        "forge", "test", "--offline", "--isolate", "--hardfork", "cancun", "--evm-version", "cancun",
        "--out", str(build / "out"), "--cache-path", str(build / "cache"),
        "--match-path", "test/showcase/ShowcaseGas.t.sol", "--match-test", "test_gas_", "-vvvv", "--json",
    ], cwd=ROOT)
    suite, = json.loads(output).values()
    for test in suite["test_results"].values():
        arena = dict(test["traces"])["Execution"]["arena"]
        traces = [node["trace"] for node in arena]
        runtime = {trace["address"]: trace["output"] for trace in traces if trace["kind"] == "CREATE"}
        writes = [
            trace for trace in traces
            if trace["depth"] == DIRECT_CALL_DEPTH and trace["kind"] == "CALL" and trace["address"] in runtime
        ]
        metrics = re.findall(r"^(.+) gas: (\d+)$", "\n".join(test["decoded_logs"]), re.MULTILINE)
        for (label, measured), call in zip(metrics, writes, strict=True):
            yield label, int(measured), call, runtime[call["address"]]


def receipt_gas(fork, accounts, block, call, bytecode):
    destination = call["address"]
    initial_state = accounts | {destination: {"balance": "0x0", "nonce": "0x1", "code": bytecode}}
    transaction = {
        "to": destination,
        "input": call["data"],
        "value": call["value"],
        "nonce": "0x0",
        "gas": block["currentGasLimit"],
        "gasPrice": block["currentBaseFee"],
        "v": "0x0", "r": "0x0", "s": "0x0",
        "secretKey": FIXTURE_KEY,
    }
    output = subprocess.check_output([
        "evm", "--verbosity", "2", "t8n", "--state.fork", fork, "--input.alloc", "stdin", "--input.env", "stdin",
        "--input.txs", "stdin", "--output.result", "stdout", "--output.alloc", "",
    ], input=json.dumps({"alloc": initial_state, "env": block, "txs": [transaction]}), text=True)
    result = json.loads(output)["result"]
    if result.get("rejected"):
        raise ValueError(f"{fork} rejected the benchmark transaction: {result['rejected']}")
    receipt, = result["receipts"]
    if int(receipt["status"], 16) != SUCCESSFUL_RECEIPT_STATUS:
        raise ValueError(f"{fork} execution failed for {destination} with input {call['data']}")
    return int(receipt["gasUsed"], 16)


def main():
    genesis = json.loads(subprocess.check_output(
        ["geth", "--dev", "dumpgenesis"], env={"PATH": os.environ["PATH"]}
    ))
    sender = subprocess.check_output(["cast", "wallet", "address", "--private-key", FIXTURE_KEY], text=True).strip()
    accounts = genesis["alloc"] | {sender: {"balance": hex(10**24)}}
    block = {
        "currentCoinbase": genesis["coinbase"],
        "currentGasLimit": genesis["gasLimit"],
        "currentBaseFee": genesis["baseFeePerGas"],
        "parentBeaconBlockRoot": "0x" + "00" * 32,
        "currentNumber": "1",
        "currentTimestamp": "1000",
        "currentRandom": "0",
        "withdrawals": [],
    }
    results = {}
    with TemporaryDirectory() as build:
        for label, measured, call, code in showcase_calls(Path(build)):
            cancun = receipt_gas("Cancun", accounts, block, call, code)
            if cancun != measured:
                raise ValueError(f"{label}: Cancun receipt used {cancun} gas, Forge measured {measured}")
            if label in results:
                raise ValueError(f"Duplicate showcase measurement: {label}")
            results[label] = cancun, receipt_gas("Amsterdam", accounts, block, call, code)
    required = {"staking raw", "staking exact uint112", "staking floor", "staking strict",
                "extreme raw", "extreme floor", "extreme strict"}
    if missing := required.difference(results):
        raise ValueError(f"Missing showcase measurements: {', '.join(sorted(missing))}")

    print("| First write | Cancun gas | Cancun saving | Projected Glamsterdam gas | Projected saving |")
    print("|---|---:|---:|---:|---:|")
    for label, measurements in results.items():
        baseline = label.split()[0] + " raw"
        row = [label]
        for gas, raw in zip(measurements, results[baseline], strict=True):
            saving = "baseline" if label == baseline else f"{(raw - gas) / raw:.2%}"
            row.extend((f"{gas:,}", saving))
        print("| " + " | ".join(row) + " |")


if __name__ == "__main__":
    main()
