.PHONY: build run test lint clean

APP_NAME := vlogclaw
BUILD_DIR := ./bin

build:
	go build -o $(BUILD_DIR)/$(APP_NAME) ./cmd/vlogclaw

run: build
	./$(BUILD_DIR)/$(APP_NAME)

test:
	go test -v -race ./...

lint:
	golangci-lint run ./...

clean:
	rm -rf $(BUILD_DIR)

tidy:
	go mod tidy

deps:
	go mod download
