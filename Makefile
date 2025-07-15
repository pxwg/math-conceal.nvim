UNAME := $(shell uname)
ARCH := $(shell uname -m)

ifeq ($(UNAME), Linux)
	EXT := so
else ifeq ($(UNAME), Darwin)
	EXT := dylib
else
	$(error Unsupported operating system: $(UNAME))
endif

# Lua versions supported by the crate
LUA_VERSIONS := lua51 lua52 lua53 lua54 luajit

# Default target
all: luajit

# Build directory
BUILD_DIR := target/release

# Lua paths for macOS
LUA_INCLUDE_DIR := /usr/local/include
LUA_LIB_DIR := /usr/local/lib

# Define build targets for each Lua version
define build_version
$(1):
	@if [ "$(UNAME)" = "Darwin" ]; then \
		RUSTFLAGS="-C link-args=-undefined -C link-args=dynamic_lookup" cargo build --release --features=$(1) -p lookup_conceal; \
	else \
		RUSTFLAGS="-C link-args=-Wl,-soname,liblookup_conceal.$(EXT)" cargo build --release --features=$(1) -p lookup_conceal; \
	fi
	@mkdir -p build
	@cp $(BUILD_DIR)/liblookup_conceal.$(EXT) build/lookup_conceal$(1).$(EXT)
	@if [ "$(UNAME)" = "Darwin" ]; then \
		install_name_tool -id @rpath/lookup_conceal$(1).$(EXT) build/lookup_conceal$(1).$(EXT); \
	fi
endef

# Generate build targets for each Lua version
$(foreach version,$(LUA_VERSIONS),$(eval $(call build_version,$(version))))

# Build all versions
all_versions: $(LUA_VERSIONS)

# Clean target
clean:
	cargo clean
	rm -rf build

# Development targets
lint:
	cargo clippy --all-features -- -D warnings

test:
	cargo test --all-features

.PHONY: all $(LUA_VERSIONS) all_versions clean lint test
