use std::ffi::CStr;

#[cfg(not(test))]
unsafe extern "C" {
    #[link_name = "ALGetGrappaToken"]
    fn al_get_grappa_token(
        in_version: u32,
        in_device_type: u32,
        in_protocol_version: u32,
        out_buf: *mut u8,
        max_len: usize,
        out_len: *mut usize,
        err_buf: *mut libc::c_char,
        err_len: usize,
    ) -> libc::c_int;
}

#[cfg(test)]
unsafe fn al_get_grappa_token(
    _in_version: u32,
    _in_device_type: u32,
    _in_protocol_version: u32,
    out_buf: *mut u8,
    max_len: usize,
    out_len: *mut usize,
    _err_buf: *mut libc::c_char,
    _err_len: usize,
) -> libc::c_int {
    let token = b"test-grappa-token";
    if out_buf.is_null() || out_len.is_null() || max_len < token.len() {
        return -1;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(token.as_ptr(), out_buf, token.len());
        *out_len = token.len();
    }
    0
}

/// Generate an authentic Grappa client token for AirTraffic sync.
///
/// Calls `ALGetGrappaToken` defined in `GrappaHelper.m` with full `@autoreleasepool`
/// and `@try/@catch` protection against Objective-C exceptions.
pub fn generate_grappa_token<F: Fn(&str)>(
    device_info: Option<(u32, u32, u32)>,
    log: F,
) -> Option<Vec<u8>> {
    unsafe {
        let (ver, dt, pv) = device_info.unwrap_or((1, 0, 1));
        let mut buf = vec![0u8; 512];
        let mut out_len: usize = 0;
        let mut err_buf = [0 as libc::c_char; 256];

        let rc = al_get_grappa_token(
            ver,
            dt,
            pv,
            buf.as_mut_ptr(),
            buf.len(),
            &mut out_len,
            err_buf.as_mut_ptr(),
            err_buf.len(),
        );

        if rc != 0 || out_len == 0 {
            let err_str = CStr::from_ptr(err_buf.as_ptr()).to_string_lossy();
            log(&format!(
                "airlift: grappa: token generation failed (rc={rc}): {err_str}"
            ));
            return None;
        }

        buf.truncate(out_len);
        log(&format!(
            "airlift: grappa: successfully generated authentic Grappa token ({out_len} bytes) ✅"
        ));
        Some(buf)
    }
}

#[cfg(test)]
mod tests {
    use super::generate_grappa_token;

    #[test]
    fn calls_linked_token_helper() {
        let token = generate_grappa_token(None, |_| {}).expect("test helper token");
        assert_eq!(token, b"test-grappa-token");
    }
}
