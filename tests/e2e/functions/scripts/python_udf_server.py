#!/usr/bin/env python3
import os

from arrow_udf import UdfServer, udf


@udf(input_types=["FLOAT64"], result_type="FLOAT64")
def double_price_py(price: float) -> float:
    return price * 2


def main() -> None:
    bind_host = os.getenv("PY_UDF_SERVER_BIND_HOST", "127.0.0.1")
    server = UdfServer(location=f"{bind_host}:8815")
    server.add_function(double_price_py)
    print(f"python udf server listening on {bind_host}:8815", flush=True)
    server.serve()


if __name__ == "__main__":
    main()
