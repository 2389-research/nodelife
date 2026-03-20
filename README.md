# NodeLife 📊✨

Welcome to the **NodeLife** repository! This project aims to create a knowledge graph built from meeting transcripts, leveraging a modern tech stack. It combines various features such as entity extraction, relationship mapping, and synchronization with Granola, all packed into a beautiful SwiftUI application for macOS.

## 🌟 Summary of the Project

NodeLife is an innovative macOS application designed to facilitate the understanding and organization of meeting notes. By transforming raw meeting transcripts into structured data, users can easily retrieve insights, visualize relationships, and navigate through their knowledge graph. The application employs state-of-the-art AI solutions to enhance the quality of entity extraction and relationship inference from natural language.

### Features:
- User-friendly interface built with SwiftUI.
- Robust backend powered by SQLite via GRDB.
- Intelligent entity and relationship extraction using LLMs (Large Language Models).
- Dual extraction modes: Quick (2-pass) and Deep (5-pass).
- Integration with Granola for direct transcript import.

## 🚀 How to Use

1. **Clone the Repository**:
    ```bash
    git clone https://github.com/harperreed/NodeLife.git
    ```
2. **Install Dependencies**:
    Ensure you have Swift Package Manager set up. Navigate to the project directory and run:
    ```bash
    swift build
    ```

3. **Run the Application**:
    To launch the application, use:
    ```bash
    swift run NodeLife
    ```

4. **Setup the Application**:
    Follow the on-screen instructions in the setup wizard to configure your data source and LLM preferences.

5. **Start Syncing**:
    Make sure Granola is installed, and begin syncing your meetings! The app will guide you through importing transcripts and creating an interactive graph.

## 🛠️ Tech Info

NodeLife is built with the following technologies:
- **Swift 6.0**: A powerful and intuitive programming language.
- **SwiftUI**: The user interface is powered by this modern framework for building app UIs.
- **GRDB v7+**: A powerful SQLite library for persistent storage.
- **macOS 14+ (Sonoma)**: Designed specifically for the latest macOS.
- **Swift Testing Framework**: Used for robust unit testing and validation of functionality throughout the codebase.

### Project Structure
- **NodeLife**: The core application that handles the user interface and overall app lifecycle.
- **NodeLifeCore**: A module that includes models, database interaction, services, and logic for data processing.

### Testing
The repository contains a comprehensive suite of tests built using Swift's testing framework, covering all major components and functionalities to ensure reliability and performance.

Feel free to dive in, contribute to the project, and help enhance the way we manage our meeting knowledge! 🚀💻

---
For any inquiries, issues, or feature requests, please open an issue on this repository, and I'll be happy to assist you! 

Happy coding! 🎉
