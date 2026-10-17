"""Mini RTS on Streamlit Community Cloud (decision D-37).

A thin page that shows the game, full width, inside Streamlit. The game is
the Godot web build published to GitHub Pages by CI after the tests pass,
so this page always shows the latest tested version. Nothing here touches
the game itself.

Deploy: share.streamlit.io -> New app -> this repository, branch main,
main file path streamlit/streamlit_app.py.
"""

import streamlit as st
import streamlit.components.v1 as components

GAME_URL = "https://abhiramreddypasam18243-lab.github.io/mini-rts/"
RELEASES_URL = "https://github.com/abhiramreddypasam18243-lab/mini-rts/releases/latest"
REPO_URL = "https://github.com/abhiramreddypasam18243-lab/mini-rts"

st.set_page_config(page_title="Mini RTS", page_icon="⚔️", layout="wide", initial_sidebar_state="collapsed")

# Hide Streamlit's own header, menu and footer, and use the whole width, so
# the page looks like the game rather than a dashboard.
st.markdown(
    """
    <style>
      #MainMenu, header, footer {visibility: hidden;}
      .block-container {padding: 0.6rem 1rem 0 1rem; max-width: 100%;}
      .stApp {background: #0a0f15;}
      .rts-bar {display: flex; justify-content: space-between; align-items: center;
                font-family: sans-serif; color: #8d9bb0; font-size: 0.9rem; margin-bottom: 0.4rem;}
      .rts-bar b {color: #e8eef5; letter-spacing: 0.15em;}
      .rts-bar a {color: #2ec4b6; text-decoration: none; margin-left: 1.2rem;}
      /* The game fills the rest of the window, whatever its height. */
      .stApp iframe {height: calc(100vh - 3.6rem) !important; min-height: 480px; border: 0; border-radius: 10px;}
    </style>
    """,
    unsafe_allow_html=True,
)

st.markdown(
    f"""
    <div class="rts-bar">
      <span><b>MINI RTS</b> &nbsp;·&nbsp; click the game first so it receives the keyboard</span>
      <span>
        <a href="{GAME_URL}" target="_blank">Open full screen ↗</a>
        <a href="{RELEASES_URL}" target="_blank">Windows download</a>
        <a href="{REPO_URL}" target="_blank">Source</a>
      </span>
    </div>
    """,
    unsafe_allow_html=True,
)

components.iframe(GAME_URL, height=760, scrolling=False)
