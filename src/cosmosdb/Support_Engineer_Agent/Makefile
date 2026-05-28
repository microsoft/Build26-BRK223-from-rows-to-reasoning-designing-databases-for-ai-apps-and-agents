PYTHON ?= python3

.PHONY: install-backend install-frontend backend frontend build-frontend check-backend

install-backend:
	$(PYTHON) -m pip install -e ../../..
	$(PYTHON) -m pip install -r backend/requirements.txt

install-frontend:
	cd frontend && npm install

backend:
	cd backend && uvicorn app:app --reload --port 8000

frontend:
	cd frontend && npm run dev

build-frontend:
	cd frontend && npm run build

check-backend:
	PYTHONPATH=backend:../../.. $(PYTHON) -m compileall backend