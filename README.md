# Trash Lens

## My phone gallery is a total mess—blurry pics, old memes, random screenshots I forgot about 😩 Have you dealt with this too?

### Trash Lens brings order to your image chaos—so you can focus on what matters and free up space effortlessly. Powered by open-source vision models and fully self-hostable, Trash Lens gives you smart, private control over your photo library.
### [Watch the demo video](https://odysee.com/@rushi:2/trash-lens:4)

![image](https://github.com/user-attachments/assets/21330817-6eef-4acf-b020-fd5dbb83d4b7)
---


## Usage

### Step 1: Set up the Backend

1. Clone the repository:
    ```bash
    git clone https://github.com/0xrushi/llama-vision-image-tagger.git
    cd llama-vision-image-tagger
    ```

2. Create and activate a virtual environment:
    ```bash
    python -m venv venv
    source venv/bin/activate  # On Windows use `venv\Scripts\activate`
    ```

3. Start the backend server:
    ```bash
    uvicorn main_flutter:app --host 0.0.0.0 --port 8000
    ```

### Step 2: Start the Ollama Server

In a separate terminal, run the following command:
```bash
ollama run llama3.2-vision:latest
```

### Step 3: Run the Application

1. Download the app from the releases.
2. Run the application.
3. Enter your backend IP in the app!
