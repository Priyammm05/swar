fn main() {
    match swar_core::api::models::install_recommended_model() {
        Ok(status) => println!("{}", status.path),
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(1);
        }
    }
}
