
# Recommender Algorithms
 ## CONTENT DISPLAY THE FEED
 * In the feed, we shall monitor user behavior, we keep monitoring the user's search, likes, follows,dislikes,and collabrations so that we understand the user's preferences and interests. We can then use this information to recommend content that is relevant to the user.
 * We can also use collaborative filtering, which is a technique that recommends content based on the preferences of similar users. For example, if user A and user B have similar preferences, we can recommend content that user A likes to user B, and vice versa.
 * We can also use content-based filtering, which is a technique that recommends content based on the attributes of the content itself. For example, if a user likes a particular type of content, we can recommend similar content based on its attributes, such as genre, topic, or format.
 * We can also use hybrid recommender systems, which combine multiple techniques to provide more accurate recommendations. For example, we can combine collaborative filtering and content-based filtering to provide more personalized recommendations.
 * We can also use machine learning algorithms, such as matrix factorization, to analyze user behavior and make recommendations based on patterns in the data. This can help us identify hidden relationships between users and content, and provide more accurate recommendations.
 * Then we dont want to cause bias in faculties since our project aims at enhancing interfaculty collaboration, we can use techniques such as diversity and serendipity to ensure that our recommendations are not limited to a narrow set of content or users. This can help us promote cross-faculty collaboration and encourage users to explore new content and connect with new people. So we can display atleast 3 recommendations of interest and the next two from other faculties randomly.
 * Now I need us to add more feture in the feed exactly where content dislays like tiktok does,, where we can search besed on name, faculty, skill, Then we can have the following tab as well,,, so users can decide to view content for the people they search, faculty content, or content relecant to a given skill.


 Then lets also implement a mechanism of tracking the user behavior like searches, following, likes, dislikes, collaboration, time for viewing content etc, we save them somewhere and the admin should be able to see them.

 We can use an efficient data structure like a tree to do this. So we can implement a tree or graphs API or any efficient data strcuture to do this for us, then wire to the admin for follow up showing how a given user behavior has been monitored.

 ## OPPORTUNITIES & COLLABORATION
Here we shall use efficient Stable Matching Algorithms. When users are registering, lets capture the skills and store them in a set (Dont allow duplicates). We only add new unique skill.

Then we're to revise our registration process as the user is posting skills, they start with the most capable to the least capable, then we can store in a map or a dictionary.

Now when opportunity is posted, the person posting opportunity should also post skills in the order of most required to least required.

So the matching is done by iterating the opportunity requirements against the students' skills and then filter the best, we push them as the most capable collaborators, then even in viewing opportunities, we select those that are related to the students' skills and thats what they should see.

We shall revise the necessary files accordingly.
