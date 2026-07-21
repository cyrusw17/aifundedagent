.PHONY: install run cli test

install:
	pip install -r requirements.txt

run:
	PYTHONPATH=. uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

cli:
	PYTHONPATH=. python scripts/run_cli.py --strategy donchian --source synthetic \
		--insample-perms 40 --walkforward-perms 20 --train-years 2

test:
	PYTHONPATH=. pytest mcpt/tests -q
