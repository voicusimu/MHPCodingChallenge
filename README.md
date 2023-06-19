# Mobile App Coding Challenge


Task

Create a mobile application. 
The app is designed to show a user all the Houses from Game of Thrones in a list.

It should be possible to select one of these houses from the table. 
    By tapping on a cell, the selected house should be displayed in a detail view. 
        There should be more information than in the master view.

APIs and Docs

The following tools are available to you for this purpose:

Game Of Thrones API: https://anapioficeandfire.com/

Requirements

    Create a native iOS app
    Code using Swift
    Deployment target iOS 14
    No third party dependencies
    Use version management (GitHub, Bitbucket) to make the project available to us.

Have fun!


Approach:

- I created a native iOS application using an MVP architecture, without the use of any third party libraries
- I added the following features:
    - basic error handling
    - Proper UI implementation for different use states: Loading, No data to display, Error
    - Pagination using the API pagination functionality (when scrolling at the bottom of the tableView)
    - Search functionality
    - A basic details view that shows the rest of the information provided by the API
