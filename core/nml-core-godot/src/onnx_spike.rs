//! ONNX runtime spike (off by default): load one exported brain from memory and
//! run one static batch of the token contract. Built only with exactly one of
//! the `onnx-tract` / `onnx-ort` features. No Godot type appears here.
//!
//! `run` returns `(value, member_values)`; `member_values` is flat row-major
//! `[rows, members]` exactly as the graph emits it.

#[cfg(all(feature = "onnx-tract", feature = "onnx-ort"))]
compile_error!("enable exactly one of the onnx-tract / onnx-ort features");

/// One static batch: six flat float32 buffers in token-contract layout.
pub struct Batch {
    pub units: Vec<f32>,      // [rows, 24, 72]
    pub units_mask: Vec<f32>, // [rows, 24]
    pub objs: Vec<f32>,       // [rows, 6, 12]
    pub objs_mask: Vec<f32>,  // [rows, 6]
    pub terr: Vec<f32>,       // [rows, 18, 12]
    pub glob: Vec<f32>,       // [rows, 16]
}

fn rows(batch: &Batch) -> usize {
    batch.units.len() / (24 * 72)
}

#[cfg(feature = "onnx-tract")]
mod imp {
    use super::{rows, Batch};
    use tract_onnx::prelude::*;

    pub struct Brain {
        plan: Arc<TypedRunnableModel>,
    }

    pub fn load(bytes: &[u8]) -> Result<Brain, String> {
        let mut reader: &[u8] = bytes;
        let plan = tract_onnx::onnx()
            .model_for_read(&mut reader)
            .map_err(err)?
            .into_optimized()
            .map_err(err)?
            .into_runnable()
            .map_err(err)?;
        Ok(Brain { plan })
    }

    impl Brain {
        pub fn run(&self, batch: &Batch) -> Result<(Vec<f32>, Vec<f32>), String> {
            let b = rows(batch);
            let tensor = |shape: &[usize], data: &[f32]| {
                Tensor::from_shape(shape, data).map(TValue::from).map_err(err)
            };
            let inputs = tvec![
                tensor(&[b, 24, 72], &batch.units)?,
                tensor(&[b, 24], &batch.units_mask)?,
                tensor(&[b, 6, 12], &batch.objs)?,
                tensor(&[b, 6], &batch.objs_mask)?,
                tensor(&[b, 18, 12], &batch.terr)?,
                tensor(&[b, 16], &batch.glob)?,
            ];
            let outputs = self.plan.run(inputs).map_err(err)?;
            let out = |i: usize| -> Result<Vec<f32>, String> {
                let view = outputs[i].to_plain_array_view::<f32>().map_err(err)?;
                Ok(view.iter().copied().collect())
            };
            Ok((out(0)?, out(1)?))
        }
    }

    fn err(e: TractError) -> String {
        format!("{e:#}")
    }
}

#[cfg(feature = "onnx-ort")]
mod imp {
    use super::{rows, Batch};
    use std::sync::{Mutex, OnceLock};

    static ORT_INIT: OnceLock<Result<(), String>> = OnceLock::new();

    pub struct Brain {
        session: Mutex<ort::session::Session>,
    }

    pub fn load(bytes: &[u8]) -> Result<Brain, String> {
        ORT_INIT
            .get_or_init(|| {
                let dylib = std::env::var("NML_ORT_DYLIB")
                    .map_err(|_| "NML_ORT_DYLIB is not set".to_string())?;
                ort::init_from(&dylib).map_err(|e| e.to_string())?.commit();
                Ok(())
            })
            .clone()?;
        let session = ort::session::Session::builder()
            .map_err(|e| e.to_string())?
            .with_intra_threads(1)
            .map_err(|e| e.to_string())?
            .with_inter_threads(1)
            .map_err(|e| e.to_string())?
            .with_parallel_execution(false)
            .map_err(|e| e.to_string())?
            .commit_from_memory(bytes)
            .map_err(|e| e.to_string())?;
        Ok(Brain { session: Mutex::new(session) })
    }

    impl Brain {
        pub fn run(&self, batch: &Batch) -> Result<(Vec<f32>, Vec<f32>), String> {
            let b = rows(batch);
            let tensor = |shape: Vec<usize>, data: &[f32]| -> Result<ort::value::Tensor<f32>, String> {
                ort::value::Tensor::from_array((shape, data.to_vec())).map_err(|e| e.to_string())
            };
            let mut session = self.session.lock().map_err(|e| e.to_string())?;
            let outputs = session
                .run(ort::inputs![
                    "units" => tensor(vec![b, 24, 72], &batch.units)?,
                    "units_mask" => tensor(vec![b, 24], &batch.units_mask)?,
                    "objs" => tensor(vec![b, 6, 12], &batch.objs)?,
                    "objs_mask" => tensor(vec![b, 6], &batch.objs_mask)?,
                    "terr" => tensor(vec![b, 18, 12], &batch.terr)?,
                    "glob" => tensor(vec![b, 16], &batch.glob)?,
                ])
                .map_err(|e| e.to_string())?;
            let value = outputs["value"]
                .try_extract_tensor::<f32>()
                .map_err(|e| e.to_string())?
                .1
                .to_vec();
            let member_values = outputs["member_values"]
                .try_extract_tensor::<f32>()
                .map_err(|e| e.to_string())?
                .1
                .to_vec();
            Ok((value, member_values))
        }
    }
}

pub use imp::{load, Brain};
