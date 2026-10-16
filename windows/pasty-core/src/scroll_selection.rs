pub struct ScrollSelection;

impl ScrollSelection {
    pub const PRECISE_THRESHOLD: f64 = 40.0;
    pub const LINE_THRESHOLD: f64 = 1.0;

    /// Upward scroll (positive `delta_y`) matches the left arrow. Downward scroll matches the right arrow.
    pub fn consume(delta_y: f64, precise: bool, accumulated: &mut f64) -> i32 {
        if !delta_y.is_finite() || delta_y == 0.0 {
            return 0;
        }
        *accumulated += delta_y;
        let threshold = if precise {
            Self::PRECISE_THRESHOLD
        } else {
            Self::LINE_THRESHOLD
        };
        let mut steps = 0i32;
        while *accumulated >= threshold {
            *accumulated -= threshold;
            steps -= 1;
        }
        while *accumulated <= -threshold {
            *accumulated += threshold;
            steps += 1;
        }
        steps
    }
}
