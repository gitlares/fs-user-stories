// SPDX-License-Identifier: MIT

use std::io::{self, Read};

use fs_user_stories_core::{Command, Response, execute};

fn main() {
    let mut input = String::new();
    if let Err(error) = io::stdin().read_to_string(&mut input) {
        print_response(Response::error("input_error", error.to_string()));
        return;
    }

    let response = match serde_json::from_str::<Command>(&input) {
        Ok(command) => execute(command).unwrap_or_else(Response::from_error),
        Err(error) => Response::error("invalid_request", error.to_string()),
    };
    print_response(response);
}

fn print_response(response: Response) {
    match serde_json::to_string(&response) {
        Ok(value) => println!("{value}"),
        Err(error) => println!(
            "{{\"ok\":false,\"error\":{{\"code\":\"encoding_error\",\"message\":{:?}}}}}",
            error.to_string()
        ),
    }
}
