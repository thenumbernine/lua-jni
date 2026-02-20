// apt install openjdk openjfx
// compile with:	javac --module-path /usr/share/openjfx/lib/ --add-modules javafx.controls,javafx.fxml TestJavaFX.java 
// run with:		java --module-path /usr/share/openjfx/lib/ --add-modules javafx.controls,javafx.fxml TestJavaFX

import javafx.application.Application;
import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;
 
public class TestJavaFX extends Application {
	public static void main(String[] args) {
		launch(args);
	}

	@Override
	public void start(Stage primaryStage) {
		primaryStage.setTitle("Hello World!");
		Button btn = new Button();
		btn.setText("Say 'Hello World'");
		btn.setOnAction(new EventHandler<ActionEvent>() {
 
			@Override
			public void handle(ActionEvent event) {
				System.out.println("Hello World!");
			}
		});
		
		StackPane root = new StackPane();
		root.getChildren().add(btn);
		primaryStage.setScene(new Scene(root, 300, 250));
		primaryStage.show();
	}
}
