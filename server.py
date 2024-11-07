from flask import Flask, request, jsonify
from flask_cors import CORS  # Add CORS support for testing

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

@app.route('/test', methods=['GET'])
def test():
    return jsonify({'status': 'Server is running!'})

@app.route('/detect', methods=['POST'])
def detect():
    # Simple test response
    if 'image' not in request.files:
        return jsonify({'error': 'No image file'}), 400
    
    # Just return a test response
    return jsonify({
        'label': 'Test Detection',
        'confidence': 0.95
    })

if __name__ == '__main__':
    # Make sure to run on all interfaces (0.0.0.0)
    app.run(host='0.0.0.0', port=5000, debug=True)