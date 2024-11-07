from flask import Flask, request, jsonify
import tensorflow as tf
import numpy as np
from PIL import Image
import io

app = Flask(__name__)

# Load TFLite model
interpreter = tf.lite.Interpreter(model_path="./assets/saved_model.tflite")
interpreter.allocate_tensors()

# Read label map from labels.txt
LABEL_MAP = {}
with open("D:/flutter-apps/finals/flutter_application_3/flutter_application_3/assets/labels.txt", "r") as file:
    for i, line in enumerate(file.readlines()):
        LABEL_MAP[i] = line.strip()

detections = [{}]
@app.route('/detect', methods=['POST'])
def detect():
    try:
        # Ensure image data is received
        if 'image' not in request.files:
            return jsonify({'error': 'No image provided'}), 400

        # Read and preprocess image
        image = Image.open(request.files['image']).convert("RGB")
        image = image.resize((224, 224))  # Resize to model input size
        image = np.array(image, dtype=np.float32)
        image = np.expand_dims(image, axis=0)  # Add batch dimension

        # Run inference
        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()
        interpreter.set_tensor(input_details[0]['index'], image)
        interpreter.invoke()
        output = interpreter.get_tensor(output_details[0]['index'])

        # Log all class predictions for debugging
        print("Model output probabilities:", output)

        # Process results
        class_id = np.argmax(output)
        confidence = float(output[0][class_id])
        label = LABEL_MAP.get(class_id, "Unknown")

        # Check if confidence meets threshold
        if confidence >= 0.75:  # Temporarily lowered for testing
            detections = [{"label": label, "confidence": confidence}]
            print("Detected label:", label, "with confidence:", confidence)
            return jsonify(detections[0])
        else:
            print("No predictions above confidence threshold.")
            return jsonify({'error': 'No predictions with confidence >= 0.75'}), 400

    except Exception as e:
        print("Failed to process image:", e)
        return jsonify({'error': 'Failed to process image', 'details': str(e)}), 500
\

@app.route('/')
def home():
    return jsonify(detections)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
