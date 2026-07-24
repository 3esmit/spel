fn main() {
    match std::env::var("CARGO_CFG_TARGET_OS").as_deref() {
        Ok("linux") => {
            // Release bundles place the exact libpython selected by pyo3 beside
            // the executable. Keep normal development builds compatible with
            // the host search path while making packaged binaries relocatable.
            println!("cargo:rustc-link-arg-bins=-Wl,-rpath,$ORIGIN/lib");
        },
        Ok("macos") => {
            println!("cargo:rustc-link-arg-bins=-Wl,-rpath,@executable_path/lib");
        },
        _ => {},
    }
}
